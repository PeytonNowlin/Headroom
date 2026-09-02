import Foundation
import HeadroomCore
import Testing

private let pricing = PricingTable(models: [
    "grok-4.6": ModelPrice(input: 2e-6, output: 6e-6, cacheWrite: 0, cacheRead: 0.5e-6),
])

@Suite("Grok spend")
struct GrokSpendTests {
    // 1787680000 = 2026-08-25T19:06:40Z; both fixture turns fall on Aug 25 local (New York).
    let now = Date(timeIntervalSince1970: 1_787_700_000)

    @Test("turn_completed records carry recorded cost, split cached input, and dedup by eventId")
    func turns() async throws {
        let world = TestWorld(now: now)
        world.file(".grok/sessions/proj/s1/updates.jsonl", Fixtures.string("grok-updates.jsonl"))
        world.file(".grok/sessions/proj/s1/chat_history.jsonl", #"{"type":"assistant","usage":{"inputTokens":999999}}"# + "\n")

        let ledger = await SpendScanner(format: GrokLogFormat(), environment: world.environment).scan()
        let day = ledger.days["2026-08-25"]!
        let build = day["grok-4.6-build"]!
        #expect(build.calls == 1)
        #expect(build.tokens == TokenTotals(input: 2_319_235 - 1_976_576, output: 27_790, cacheWrite: 0, cacheRead: 1_976_576))
        #expect(abs(build.recordedCost - 0.31285882) < 1e-6)

        let summary = SpendSummarizer.summarize(ledger, pricing: pricing, now: now, calendar: world.environment.calendar)
        // Recorded cost wins for the build model; the unpriced-by-ticks turn falls back to the table
        // via the -build suffix rule when no ticks exist, or directly for grok-4.6.
        #expect(abs(summary.today.cost - (0.31285882 + 1000 * 2e-6 + 100 * 6e-6)) < 1e-6)
        #expect(summary.today.calls == 2)
        #expect(summary.today.unpricedTokens == 0)
    }

    @Test("subagent sessions are skipped; sessions without a summary or kind are kept")
    func subagents() async throws {
        let world = TestWorld(now: now)
        world.file(".grok/sessions/proj/parent/updates.jsonl", Fixtures.string("grok-updates.jsonl"))
        world.file(".grok/sessions/proj/parent/summary.json", #"{"session_kind":null}"#)
        world.file(".grok/sessions/proj/child/updates.jsonl", Fixtures.string("grok-updates.jsonl"))
        world.file(".grok/sessions/proj/child/summary.json", #"{"session_kind":"subagent"}"#)
        world.file(".grok/sessions/proj/orphan/updates.jsonl", Fixtures.string("grok-updates.jsonl"))

        let ledger = await SpendScanner(format: GrokLogFormat(), environment: world.environment).scan()
        #expect(ledger.days["2026-08-25"]?["grok-4.6-build"]?.calls == 2)
    }

    @Test("GROK_HOME relocates the sessions root; -build falls back to the base model price")
    func homeAndPricing() async throws {
        let world = TestWorld(now: now)
        world.env("GROK_HOME", "/Users/test/alt-grok")
        world.absoluteFile("/Users/test/alt-grok/sessions/p/s/updates.jsonl", Fixtures.string("grok-updates.jsonl"))
        let scanner = SpendScanner(format: GrokLogFormat(), environment: world.environment)
        #expect(scanner.hasLogs())
        let ledger = await scanner.scan()
        #expect(ledger.days.isEmpty == false)
        #expect(pricing.price(for: "grok-4.6-build") == pricing.price(for: "grok-4.6"))
    }
}
