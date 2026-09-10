import Foundation
import HeadroomCore
import Testing

/// `[created_ms, cost, model, input, output, reasoning, cacheWrite, cacheRead]`, the shape the
/// `json_group_array` in `OpenCodeSpendSource.usageSQL` produces.
private func rows(_ rows: [(Double, Double, String, Int, Int, Int, Int, Int)]) -> String {
    "[" + rows.map { r in
        "[\(Int(r.0)),\(r.1),\"\(r.2)\",\(r.3),\(r.4),\(r.5),\(r.6),\(r.7)]"
    }.joined(separator: ",") + "]"
}

@Suite("OpenCode spend")
struct OpenCodeSpendTests {
    private func world() -> TestWorld { TestWorld() }

    @Test("sums the recorded cost per model per day and folds reasoning into output tokens")
    func ledgerFromDatabase() async throws {
        let world = world()
        let nowMs = world.now.timeIntervalSince1970 * 1000
        world.database(".local/share/opencode/opencode.db", result: rows([
            (nowMs, 0.25, "grok-code", 100, 40, 10, 5, 900),
            (nowMs, 0.75, "grok-code", 200, 60, 0, 0, 100),
            (nowMs - 86_400_000, 1.5, "kimi-k3", 10, 20, 0, 0, 0),
        ]))

        let ledger = try #require(await OpenCodeSpendSource(environment: world.environment).ledger())
        let calendar = world.environment.calendar
        let today = SpendLedger.dayKey(world.now, calendar: calendar)
        let yesterday = SpendLedger.dayKey(world.now.addingTimeInterval(-86_400), calendar: calendar)

        let grok = try #require(ledger.days[today]?["grok-code"])
        #expect(grok.calls == 2)
        #expect(grok.recordedCost == 1.0)
        #expect(grok.tokens == TokenTotals(input: 300, output: 110, cacheWrite: 5, cacheRead: 1000))
        #expect(ledger.days[yesterday]?["kimi-k3"]?.recordedCost == 1.5)

        // Recorded cost wins over pricing, so the tile is exactly what OpenCode billed.
        let summary = SpendSummarizer.summarize(ledger, pricing: PricingTable(models: [:]), now: world.now, calendar: calendar)
        #expect(summary.today.cost == 1.0)
        #expect(summary.today.tokens == 1415)
        #expect(summary.yesterday.cost == 1.5)
    }

    @Test("queries every channel database and asks only for hosted rows inside the 30-day window")
    func queryShapeAndChannels() async throws {
        let world = world()
        let nowMs = world.now.timeIntervalSince1970 * 1000
        world.database(".local/share/opencode/opencode.db", result: rows([(nowMs, 1, "a", 1, 1, 0, 0, 0)]))
        world.database(".local/share/opencode/opencode-next.db", result: rows([(nowMs, 2, "a", 1, 1, 0, 0, 0)]))
        // Sidecars and unrelated files are not databases.
        world.file(".local/share/opencode/opencode.db-wal", "junk")
        world.file(".local/share/opencode/auth.json", "{}")

        let ledger = try #require(await OpenCodeSpendSource(environment: world.environment).ledger())
        let today = SpendLedger.dayKey(world.now, calendar: world.environment.calendar)
        #expect(ledger.days[today]?["a"]?.recordedCost == 3)

        let paths = world.queries.map { URL(filePath: $0.path).lastPathComponent }
        #expect(paths == ["opencode-next.db", "opencode.db"])
        let sql = try #require(world.queries.first?.sql)
        #expect(sql.contains("'opencode','opencode-go'"))
        #expect(sql.contains("'assistant'"))
        let cutoff = world.environment.calendar.date(
            byAdding: .day, value: -29, to: world.environment.calendar.startOfDay(for: world.now))!
        #expect(sql.contains(String(Int(cutoff.timeIntervalSince1970 * 1000))))
    }

    @Test("rows older than the window, negative costs, and unnamed models are dropped")
    func rejectsBadRows() async throws {
        let world = world()
        let nowMs = world.now.timeIntervalSince1970 * 1000
        world.database(".local/share/opencode/opencode.db", result: rows([
            (nowMs, 0.5, "good", 1, 1, 0, 0, 0),
            (nowMs - 60 * 86_400_000, 9, "ancient", 1, 1, 0, 0, 0),
            (nowMs, -1, "refund", 1, 1, 0, 0, 0),
            (nowMs, 1, "", 1, 1, 0, 0, 0),
        ]))
        let ledger = try #require(await OpenCodeSpendSource(environment: world.environment).ledger())
        #expect(ledger.days.values.flatMap { $0.keys }.sorted() == ["good"])
    }

    @Test("no database is nil; an unreadable one keeps the cached numbers; reads are throttled")
    func absenceAndFailures() async throws {
        let empty = world()
        #expect(await OpenCodeSpendSource(environment: empty.environment).ledger() == nil)
        #expect(OpenCodeSpendSource(environment: empty.environment).hasLogs() == false)

        let world = world()
        let nowMs = world.now.timeIntervalSince1970 * 1000
        world.database(".local/share/opencode/opencode.db", result: rows([(nowMs, 4, "a", 1, 1, 0, 0, 0)]))
        let source = OpenCodeSpendSource(environment: world.environment)
        #expect(source.hasLogs() == true)
        _ = await source.ledger()
        _ = await source.ledger()
        #expect(world.queries.count == 1, "a second read inside the interval reuses the cache")
        world.advance(by: OpenCodeSpendSource.interval + 1)
        _ = await source.ledger()
        #expect(world.queries.count == 2)

        // A database that refuses the query keeps the last good ledger rather than emptying tiles.
        let unreadable = TestWorld()
        unreadable.file(".local/share/opencode/opencode.db", "sqlite")
        let ledger = await OpenCodeSpendSource(environment: unreadable.environment).ledger()
        #expect(ledger == SpendLedger())
    }

    @Test("the cached ledger survives a relaunch")
    func cachePersists() async throws {
        let world = world()
        let nowMs = world.now.timeIntervalSince1970 * 1000
        world.database(".local/share/opencode/opencode.db", result: rows([(nowMs, 2.5, "a", 1, 1, 0, 0, 0)]))
        _ = await OpenCodeSpendSource(environment: world.environment).ledger()

        // Relaunch: the database now refuses reads, so only the cache can answer.
        let relaunched = OpenCodeSpendSource(environment: world.environment)
        world.state.withLock { $0.queryResults = [:] }
        let ledger = try #require(await relaunched.ledger())
        let today = SpendLedger.dayKey(world.now, calendar: world.environment.calendar)
        #expect(ledger.days[today]?["a"]?.recordedCost == 2.5)
    }
}
