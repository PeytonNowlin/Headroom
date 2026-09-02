import Foundation
import HeadroomCore
import Testing

private let pricing = PricingTable(models: [
    "claude-opus-5": ModelPrice(input: 5e-6, output: 25e-6, cacheWrite: 6.25e-6, cacheRead: 0.5e-6),
    "claude-sonnet-5": ModelPrice(input: 3e-6, output: 15e-6, cacheWrite: 3.75e-6, cacheRead: 0.3e-6),
])

/// 2026-09-02 00:20 America/New_York (04:20Z). The fixture's first reply is 22:30 the previous
/// evening local time, its second is 00:15 today.
private let localMidnightish = DateParsing.iso8601("2026-09-02T04:20:00Z")!

@Suite("Claude spend")
struct ClaudeSpendTests {
    @Test("streamed duplicates count once, synthetic records are skipped, days are local")
    func parseAndBucket() async throws {
        let world = TestWorld(now: localMidnightish)
        world.file(".claude/projects/-proj/s1.jsonl", Fixtures.string("claude-session.jsonl"))

        let scanner = SpendScanner(format: ClaudeLogFormat(), environment: world.environment)
        let ledger = await scanner.scan()
        let summary = SpendSummarizer.summarize(ledger, pricing: pricing, now: world.now, calendar: world.environment.calendar)

        // msg_A landed at 22:30 local on Sep 1 → yesterday. msg_B at 00:15 local Sep 2 → today.
        #expect(summary.yesterday.calls == 1)
        #expect(summary.yesterday.tokens == 2 + 15989 + 28799 + 280)
        #expect(abs(summary.yesterday.cost - (2 * 5e-6 + 280 * 25e-6 + 15989 * 6.25e-6 + 28799 * 0.5e-6)) < 1e-9)
        #expect(summary.today.calls == 1)
        #expect(summary.today.tokens == 1500)
        #expect(abs(summary.today.cost - (1000 * 3e-6 + 500 * 15e-6)) < 1e-9)
        #expect(summary.last30Days.calls == 2)
        #expect(summary.dailyCost.count == 30)
        #expect(summary.dailyCost.last == summary.today.cost)
    }

    @Test("a window with no records is No data, not $0.00")
    func noData() async throws {
        let world = TestWorld(now: localMidnightish)
        world.file(".claude/projects/-proj/s1.jsonl", Fixtures.string("claude-session.jsonl"))
        let ledger = await SpendScanner(format: ClaudeLogFormat(), environment: world.environment).scan()

        let later = DateParsing.iso8601("2026-09-10T12:00:00Z")!
        let summary = SpendSummarizer.summarize(ledger, pricing: pricing, now: later, calendar: world.environment.calendar)
        #expect(summary.today.hasData == false)
        #expect(summary.yesterday.hasData == false)
        #expect(summary.last30Days.hasData == true)
    }

    @Test("rescans read only appended bytes, pick up new files, and survive a partial line")
    func incremental() async throws {
        let world = TestWorld(now: localMidnightish)
        world.file(".claude/projects/-proj/s1.jsonl", Fixtures.string("claude-session.jsonl"))
        let scanner = SpendScanner(format: ClaudeLogFormat(), environment: world.environment)
        _ = await scanner.scan()
        #expect(world.fileContents("Library/Application Support/Headroom/spend-claude.json") != nil)

        // Partial line: not yet counted.
        world.append(".claude/projects/-proj/s1.jsonl", #"{"type":"assistant","message":{"id":"msg_C","model":"claude-sonnet-5","usage":{"input_tokens":10,"output_tokens":10}},"timestamp":"2026-09-02T04:18:00.000Z""#)
        var ledger = await scanner.scan()
        var summary = SpendSummarizer.summarize(ledger, pricing: pricing, now: world.now, calendar: world.environment.calendar)
        #expect(summary.today.calls == 1)

        // Line completed plus a second session file: both counted, earlier lines not double counted.
        world.append(".claude/projects/-proj/s1.jsonl", "}\n")
        world.file(".claude/projects/-other/s2.jsonl", #"{"type":"assistant","message":{"id":"msg_D","model":"claude-opus-5","usage":{"input_tokens":100,"output_tokens":100}},"timestamp":"2026-09-02T04:19:00.000Z"}"# + "\n")
        ledger = await scanner.scan()
        summary = SpendSummarizer.summarize(ledger, pricing: pricing, now: world.now, calendar: world.environment.calendar)
        #expect(summary.today.calls == 3)
        #expect(summary.today.tokens == 1500 + 20 + 200)
        #expect(summary.yesterday.calls == 1)

        // A fresh scanner reloads the cache and reports the same totals without rereading.
        let reloaded = SpendScanner(format: ClaudeLogFormat(), environment: world.environment)
        let again = await reloaded.scan()
        #expect(again == ledger)
    }

    @Test("unknown models are counted in tokens but flagged unpriced")
    func unpriced() async throws {
        var ledger = SpendLedger()
        ledger.add(UsageEvent(date: localMidnightish, model: "claude-future-9", tokens: TokenTotals(input: 10, output: 10)),
                   calendar: TimeZone(identifier: "America/New_York").map { var c = Calendar(identifier: .gregorian); c.timeZone = $0; return c }!)
        let summary = SpendSummarizer.summarize(ledger, pricing: pricing, now: localMidnightish,
                                                calendar: { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }())
        #expect(summary.today.tokens == 20)
        #expect(summary.today.unpricedTokens == 20)
        #expect(summary.today.cost == 0)
        #expect(summary.today.hasData)
    }
}

@Suite("Pricing")
struct PricingTests {
    @Test("bundled snapshot knows the models we actually use")
    func bundled() {
        let table = PricingTable.bundled()
        #expect(table.price(for: "claude-opus-5") != nil)
        #expect(table.price(for: "claude-sonnet-5") != nil)
        #expect(table.price(for: "gpt-5.5") != nil)
        #expect(table.price(for: "gpt-5.3-codex") != nil)
        #expect(table.price(for: "grok-4.6") != nil)
    }

    @Test("lookup tolerates provider prefixes, date suffixes, and -latest")
    func normalization() {
        let table = PricingTable(models: ["claude-opus-5": ModelPrice(input: 1, output: 1)])
        #expect(table.price(for: "anthropic/claude-opus-5") != nil)
        #expect(table.price(for: "claude-opus-5-20260101") != nil)
        #expect(table.price(for: "claude-opus-5-latest") != nil)
        #expect(table.price(for: "Claude-Opus-5") != nil)
        #expect(table.price(for: "claude-opus-6") == nil)
    }

    @Test("LiteLLM and models.dev parse and merge with fetched prices winning over bundled")
    func sources() async throws {
        let now = Date(timeIntervalSince1970: 1_788_300_000)
        let lite = try PricingSource.liteLLM(Data(#"""
        {"claude-opus-5":{"input_cost_per_token":0.000005,"output_cost_per_token":0.000025,"cache_read_input_token_cost":5e-7,"litellm_provider":"anthropic"},
         "xai/grok-4.6":{"input_cost_per_token":0.000002,"output_cost_per_token":0.000006,"litellm_provider":"xai"},
         "gemini-x":{"input_cost_per_token":1,"output_cost_per_token":1,"litellm_provider":"gemini"}}
        """#.utf8), at: now)
        #expect(lite.models.count == 2)
        #expect(lite.models["grok-4.6"]?.output == 0.000006)

        let md = try PricingSource.modelsDev(Data(#"""
        {"openai":{"models":{"gpt-5.3-codex":{"cost":{"input":1.25,"output":10,"cache_read":0.125}}}},"anthropic":{"models":{}},"xai":{"models":{}}}
        """#.utf8), at: now)
        #expect(md.models["gpt-5.3-codex"] == ModelPrice(input: 1.25e-6, output: 10e-6, cacheWrite: 0, cacheRead: 0.125e-6))

        let world = TestWorld(now: now)
        world.respond(PricingSource.liteLLMURL.absoluteString, json: #"{"claude-opus-5":{"input_cost_per_token":0.000009,"output_cost_per_token":0.000025,"litellm_provider":"anthropic"}}"#)
        world.respond(PricingSource.modelsDevURL.absoluteString, status: 500, json: "{}")
        let bundled = PricingTable(models: ["claude-opus-5": ModelPrice(input: 1, output: 1), "other": ModelPrice(input: 2, output: 2)])
        let store = PricingStore(environment: world.environment, bundled: bundled)
        let table = await store.refreshIfNeeded()
        #expect(table.price(for: "claude-opus-5")?.input == 0.000009)
        #expect(table.price(for: "other")?.input == 2)

        // Within the hour, no second fetch.
        _ = await store.refreshIfNeeded()
        #expect(world.requests.count == 2)
        #expect(world.fileContents("Library/Application Support/Headroom/pricing-cache.json") != nil)
    }
}
