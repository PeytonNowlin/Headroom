import Foundation
import HeadroomCore
import Synchronization
import Testing

@Suite("Spend trends")
struct SpendTrendTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))! }
    private let pricing = PricingTable(models: ["priced": ModelPrice(input: 0.001, output: 0.002)])

    @Test("seven and thirty calendar days preserve missing data and DST boundaries")
    func calendarWindows() {
        var ledger = SpendLedger()
        ledger.add(UsageEvent(date: now, model: "priced", tokens: TokenTotals(input: 100)), calendar: calendar)
        ledger.add(UsageEvent(date: calendar.date(byAdding: .day, value: -10, to: now)!, model: "priced", tokens: TokenTotals(input: 200)), calendar: calendar)
        let week = SpendTrend.make(ledger, pricing: pricing, now: now, calendar: calendar, period: .week)
        let month = SpendTrend.make(ledger, pricing: pricing, now: now, calendar: calendar, period: .month)
        #expect(week.days.count == 7)
        #expect(month.days.count == 30)
        #expect(Set(month.days.map { calendar.component(.day, from: $0.date) }).count >= 28)
        #expect(week.days.dropLast().allSatisfy { !$0.tile.hasData })
        #expect(week.total.tokens == 100)
        #expect(month.total.tokens == 300)
        #expect(month.days.contains { day in month.days.contains { $0.date.timeIntervalSince(day.date) == 23 * 3600 } })
    }

    @Test("model attribution uses each day's recorded cost or estimate without dropping unpriced tokens")
    func attribution() {
        var ledger = SpendLedger()
        ledger.add(UsageEvent(date: now, model: "priced", tokens: TokenTotals(input: 100), recordedCost: 2), calendar: calendar)
        ledger.add(UsageEvent(date: calendar.date(byAdding: .day, value: -1, to: now)!, model: "priced", tokens: TokenTotals(input: 100)), calendar: calendar)
        ledger.add(UsageEvent(date: now, model: "unknown", tokens: TokenTotals(input: 50)), calendar: calendar)
        let trend = SpendTrend.make(ledger, pricing: pricing, now: now, calendar: calendar, period: .week)
        #expect(abs(trend.total.cost - 2.1) < 0.00001)
        #expect(trend.models.first?.name == "priced")
        #expect(trend.models.last?.tile.unpricedTokens == 50)
        #expect(trend.models.reduce(SpendTile.empty) { $0 + $1.tile } == trend.total)
        let summary = SpendSummarizer.summarize(ledger, pricing: pricing, now: now, calendar: calendar)
        #expect(trend.total == summary.last30Days)
    }

    @Test("combined providers retain model attribution and daily totals")
    func combined() throws {
        var a = SpendLedger()
        var b = SpendLedger()
        a.add(UsageEvent(date: now, model: "priced", tokens: TokenTotals(input: 100)), calendar: calendar)
        b.add(UsageEvent(date: now, model: "priced", tokens: TokenTotals(input: 200)), calendar: calendar)
        let trends = [a, b].map { SpendTrend.make($0, pricing: pricing, now: now, calendar: calendar, period: .week) }
        let combined = try #require(SpendTrend.combine(trends))
        #expect(combined.days.count == 7)
        #expect(combined.models.count == 1)
        #expect(combined.total.tokens == 300)
        #expect(combined.models[0].tile == combined.total)
        #expect(SpendTrend.combine([]) == nil)
    }

    @Test("unchanged scans do not reread log bytes or rewrite the cache")
    func idleScan() async {
        let world = TestWorld(now: now)
        world.file(".claude/projects/test/session.jsonl", "{\"type\":\"assistant\",\"timestamp\":\"2026-03-10T16:00:00Z\",\"message\":{\"id\":\"m1\",\"model\":\"priced\",\"usage\":{\"input_tokens\":100,\"output_tokens\":10}}}\n")
        let writes = Mutex(0)
        let reads = Mutex(0)
        var environment = world.environment
        let originalWrite = environment.writeFile
        let originalRead = environment.readFileRange
        environment.writeFile = { url, data in writes.withLock { $0 += 1 }; try originalWrite(url, data) }
        environment.readFileRange = { url, offset in reads.withLock { $0 += 1 }; return try originalRead(url, offset) }
        let scanner = SpendScanner(format: ClaudeLogFormat(), environment: environment)
        let first = await scanner.scan()
        #expect(first.days.count == 1)
        #expect(writes.withLock { $0 } == 1)
        #expect(reads.withLock { $0 } == 1)
        for _ in 0..<3 { #expect(await scanner.scan() == first) }
        #expect(writes.withLock { $0 } == 1)
        #expect(reads.withLock { $0 } == 1)
        world.advance(by: 40 * 86400)
        #expect(await scanner.scan().days.isEmpty)
    }
}
