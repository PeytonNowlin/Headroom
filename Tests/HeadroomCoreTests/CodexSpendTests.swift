import Foundation
import HeadroomCore
import Testing

private let pricing = PricingTable(models: [
    "gpt-5.6-sol": ModelPrice(input: 5e-6, output: 30e-6, cacheWrite: 0, cacheRead: 0.5e-6),
])

@Suite("Codex spend")
struct CodexSpendTests {
    let now = DateParsing.iso8601("2026-09-02T04:00:00Z")!

    @Test("per-call deltas are attributed to the turn's model, cached input is split out, re-emitted counts are ignored")
    func rollout() async throws {
        let world = TestWorld(now: now)
        world.file(".codex/sessions/2026/09/01/rollout-a.jsonl", Fixtures.string("codex-rollout.jsonl"))

        let ledger = await SpendScanner(format: CodexLogFormat(), environment: world.environment).scan()
        let day = ledger.days["2026-09-01"]!
        let sol = day["gpt-5.6-sol"]!
        #expect(sol.calls == 2)
        #expect(sol.tokens == TokenTotals(input: (18464 - 6912) + (21085 - 18176), output: 146 + 159, cacheWrite: 0, cacheRead: 6912 + 18176))
        let spark = day["gpt-5.3-codex-spark"]!
        #expect(spark.calls == 1)
        #expect(spark.tokens == TokenTotals(input: 1000, output: 100))

        let summary = SpendSummarizer.summarize(ledger, pricing: pricing, now: now, calendar: world.environment.calendar)
        #expect(summary.yesterday.calls == 3)
        #expect(summary.yesterday.unpricedTokens == 1100)
        let expected = Double(sol.tokens.input) * 5e-6 + Double(sol.tokens.output) * 30e-6 + Double(sol.tokens.cacheRead) * 0.5e-6
        #expect(abs(summary.yesterday.cost - expected) < 1e-9)
    }

    @Test("the model carries across an incremental scan boundary and CODEX_HOME relocates the roots")
    func carryAndHome() async throws {
        let world = TestWorld(now: now)
        world.env("CODEX_HOME", "/Users/test/alt-codex")
        let lines = Fixtures.string("codex-rollout.jsonl").split(separator: "\n").map(String.init)
        // Everything up to and including the first turn_context, then the first token_count later.
        world.absoluteFile("/Users/test/alt-codex/sessions/2026/09/01/r.jsonl", lines[0...2].joined(separator: "\n") + "\n")
        let scanner = SpendScanner(format: CodexLogFormat(), environment: world.environment)
        #expect(scanner.hasLogs())
        var ledger = await scanner.scan()
        #expect(ledger.days.isEmpty)

        world.absoluteFile("/Users/test/alt-codex/sessions/2026/09/01/r.jsonl", lines[0...3].joined(separator: "\n") + "\n")
        ledger = await scanner.scan()
        #expect(ledger.days["2026-09-01"]?["gpt-5.6-sol"]?.calls == 1)
    }
}
