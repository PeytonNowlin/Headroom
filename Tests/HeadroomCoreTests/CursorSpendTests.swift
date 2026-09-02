import Foundation
@testable import HeadroomCore
import Testing

private let stateDB = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
private let exportPrefix = "https://cursor.com/api/dashboard/export-usage-events-csv?"

private func jwt(sub: String = "auth0|user_01ABC") -> String {
    func b64(_ s: String) -> String {
        Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    return "\(b64(#"{"alg":"RS256"}"#)).\(b64(#"{"exp":1800000000,"sub":"\#(sub)"}"#)).sig"
}

@Suite("Cursor spend")
struct CursorSpendTests {
    // 2026-09-01 12:00 UTC = 08:00 New York.
    private let now = Date(timeIntervalSince1970: 1_788_264_000)

    @Test("parses the export: thousands separators, empty cells, and rejects non-integer counts")
    func parse() throws {
        let result = try CursorUsageCSV.parse(Fixtures.string("cursor-usage-events.csv"))
        #expect(result.rejectedRows == 2)
        #expect(result.events.count == 5)
        #expect(result.events[0].model == "claude-4.6-opus-high-thinking")
        #expect(result.events[0].tokens == TokenTotals(input: 300, output: 450, cacheWrite: 1200, cacheRead: 8000))
        #expect(result.events[2].tokens.input == 0)
        #expect(result.events[3].model == "Composer 2.5 (Auto, 1 request)")
        #expect(result.events.allSatisfy { $0.dedupKey == nil && $0.recordedCost == nil })
    }

    @Test("a missing required column or a stray quote fails the whole export")
    func schema() {
        #expect(throws: CursorUsageCSV.ParseError.missingColumns(["Input (w/ Cache Write)", "Input (w/o Cache Write)", "Cache Read", "Output Tokens"])) {
            try CursorUsageCSV.parse("Date,Model,Note\n2026-01-01T00:00:00Z,composer,x\n")
        }
        #expect(throws: CursorUsageCSV.ParseError.malformed) {
            try CursorUsageCSV.parse("Date,Model,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens\n2026-01-01T00:00:00Z,com\"poser,1,1,1,1\n")
        }
    }

    @Test("Cursor slugs resolve through the supplement's alias rules and fast multipliers")
    func aliasPricing() {
        let table = PricingTable.bundled()
        #expect(table.canonicalName(for: "claude-4.6-opus-high-thinking") == "claude-opus-4-6")
        #expect(table.canonicalName(for: "composer") == "composer-2.5")
        #expect(table.canonicalName(for: "Composer 2.5 (Auto, 1 request)") == "composer-2.5")
        #expect(table.canonicalName(for: "gpt-5.5-high-fast") == "gpt-5.5-fast")

        let composer = table.price(for: "composer")
        #expect(composer?.input == 0.5 / 1_000_000)
        #expect(composer?.output == 2.5 / 1_000_000)

        let base = table.price(for: "gpt-5.5")!
        let fast = table.price(for: "gpt-5.5-high-fast")!
        #expect(abs(fast.input / base.input - 2.5) < 1e-9)
        #expect(abs(fast.output / base.output - 2.5) < 1e-9)
        #expect(table.price(for: "mystery-model-9") == nil)
    }

    @Test("the source sends the session cookie and a 30-day window, buckets by local day, and prices rows")
    func source() async throws {
        let world = TestWorld(now: now)
        world.stateValue(stateDB, "cursorAuth/accessToken", jwt())
        world.respondToEverything(HTTPResponse(statusCode: 200, body: Fixtures.data("cursor-usage-events.csv")))

        let source = CursorSpendSource(environment: world.environment)
        #expect(source.hasCredentials())
        let ledger = try #require(await source.ledger())

        let request = try #require(world.requests.first)
        #expect(request.url.absoluteString.hasPrefix(exportPrefix))
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.contains(URLQueryItem(name: "strategy", value: "tokens")))
        #expect(query.contains(URLQueryItem(name: "endDate", value: "1788264000000")))
        // 29 days before local midnight (2026-08-03 00:00 New York = 04:00 UTC).
        #expect(query.contains(URLQueryItem(name: "startDate", value: "1785729600000")))
        #expect(request.headers["Cookie"] == "WorkosCursorSessionToken=user_01ABC%3A%3A\(jwt())")
        #expect(request.headers["Accept"] == "text/csv")

        // 23:30 UTC Aug 31 is 19:30 Aug 31 New York; 02:15 UTC Sep 1 is 22:15 Aug 31 New York.
        #expect(ledger.days["2026-08-31"]?.keys.sorted() == ["claude-4.6-opus-high-thinking", "composer"])
        #expect(ledger.days["2026-09-01"]?.keys.sorted() == ["Composer 2.5 (Auto, 1 request)", "gpt-5.5-high-fast", "mystery-model-9"])

        let summary = SpendSummarizer.summarize(ledger, pricing: .bundled(), now: now, calendar: world.environment.calendar)
        #expect(summary.today.tokens == 2000 + 4000 + 600 + 110 + 40)
        #expect(summary.today.unpricedTokens == 40)
        #expect(summary.today.cost > 0)
        #expect(summary.yesterday.tokens == 9950 + 26900)
        #expect(summary.last30Days.hasData)
    }

    @Test("a failed export keeps the cached ledger; no login means no ledger; fetches are throttled")
    func cachingAndThrottle() async throws {
        let world = TestWorld(now: now)
        world.stateValue(stateDB, "cursorAuth/accessToken", jwt())
        world.respondToEverything(HTTPResponse(statusCode: 200, body: Fixtures.data("cursor-usage-events.csv")))
        let first = CursorSpendSource(environment: world.environment)
        let fetched = try #require(await first.ledger())
        #expect(world.requests.count == 1)

        _ = await first.ledger()
        #expect(world.requests.count == 1)  // within the 5-minute window

        world.advance(by: CursorSpendSource.interval + 1)
        world.respondToEverything(HTTPResponse(statusCode: 500))
        let afterFailure = try #require(await first.ledger())
        #expect(world.requests.count == 2)
        #expect(afterFailure == fetched)

        // A fresh instance restores the on-disk cache even when the network is down.
        let second = CursorSpendSource(environment: world.environment)
        world.advance(by: CursorSpendSource.interval + 1)
        #expect(await second.ledger() == fetched)

        let signedOut = CursorSpendSource(environment: TestWorld(now: now).environment)
        #expect(!signedOut.hasCredentials())
        #expect(await signedOut.ledger() == nil)
    }
}
