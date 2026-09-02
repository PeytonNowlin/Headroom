import Foundation
import HeadroomCore
import Testing

private let usageURL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
private let planURL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo"
private let grokBotURL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus"
private let requestUsageURL = "https://cursor.com/api/usage?user=user_01ABC"
private let stateDB = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"

private func jwt(exp: Date, sub: String = "auth0|user_01ABC") -> String {
    let header = Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8).base64URL
    let payload = Data(#"{"exp":\#(Int(exp.timeIntervalSince1970)),"sub":"\#(sub)"}"#.utf8).base64URL
    return "\(header).\(payload).sig"
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

@Suite("Cursor provider")
struct CursorProviderTests {
    private func world(token: String? = nil) -> TestWorld {
        let world = TestWorld()
        if let token { world.stateValue(stateDB, "cursorAuth/accessToken", token) }
        return world
    }

    @Test("reads the state database token, speaks Connect, and maps plan windows and on-demand spend")
    func mapsUsage() async throws {
        let world = world(token: jwt(exp: Date(timeIntervalSince1970: 1_800_000_000)))
        world.respond(usageURL, fixture: "cursor-usage.json")
        world.respond(planURL, fixture: "cursor-plan.json")
        world.respond(grokBotURL, fixture: "cursor-grok-bot.json")

        let snapshot = try await CursorProvider(environment: world.environment).refresh()

        let usage = try #require(world.requests.first { $0.url.absoluteString == usageURL })
        #expect(usage.method == "POST")
        #expect(usage.headers["Connect-Protocol-Version"] == "1")
        #expect(usage.headers["Authorization"]?.hasPrefix("Bearer ey") == true)

        #expect(snapshot.status == .connected)
        #expect(snapshot.planName == "Pro Plus")
        #expect(snapshot.windows.map(\.id) == ["included", "auto", "api", "grok-bot"])
        #expect(snapshot.windows[0].usedPercent == 64.2)
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_789_592_000))
        #expect(snapshot.windows[0].duration == 2_592_000)
        #expect(snapshot.windows[1].title == "Cursor models")
        #expect(snapshot.windows[1].usedPercent == 91.5)
        #expect(snapshot.windows[3].usedPercent == 37.5)
        #expect(snapshot.windows[3].duration == 7 * 86400.0)
        #expect(snapshot.ringUsedPercent == 91.5)
        #expect(snapshot.extraUsage == ExtraUsage(isEnabled: true, usedDollars: 13.75, limitDollars: 50))
        #expect(Formatting.extraUsage(snapshot.extraUsage!) == "$13.75 of $50.00")
    }

    @Test("falls back to the keychain item when the state database has no token")
    func keychainFallback() async throws {
        let world = TestWorld()
        world.keychain("cursor-access-token", jwt(exp: Date(timeIntervalSince1970: 1_800_000_000)) + "\n")
        world.respond(usageURL, fixture: "cursor-usage.json")
        world.respondToEverything(HTTPResponse(statusCode: 404))

        let provider = CursorProvider(environment: world.environment)
        #expect(provider.hasLocalCredentials())
        let snapshot = try await provider.refresh()
        #expect(snapshot.status == .connected)
        #expect(snapshot.planName == nil)
        #expect(snapshot.windows.count == 3)  // optional endpoints failing never drop the primary
    }

    @Test("the state database wins over the keychain")
    func databasePriority() async throws {
        let world = world(token: jwt(exp: Date(timeIntervalSince1970: 1_800_000_000), sub: "auth0|db-user"))
        world.keychain("cursor-access-token", jwt(exp: Date(timeIntervalSince1970: 1_800_000_000), sub: "auth0|kc-user"))
        world.respond(usageURL, fixture: "cursor-usage.json")
        world.respondToEverything(HTTPResponse(statusCode: 404))

        _ = try await CursorProvider(environment: world.environment).refresh()
        let auth = world.requests[0].headers["Authorization"]!
        #expect(auth.contains(Data(#"{"exp":1800000000,"sub":"auth0|db-user"}"#.utf8).base64URL))
    }

    @Test("request-based enterprise plans use cursor.com/api/usage with the session cookie")
    func enterpriseFallback() async throws {
        let token = jwt(exp: Date(timeIntervalSince1970: 1_800_000_000))
        let world = world(token: token)
        world.respond(usageURL, fixture: "cursor-usage-enterprise.json")
        world.respond(requestUsageURL, fixture: "cursor-request-usage.json")
        world.respondToEverything(HTTPResponse(statusCode: 404))

        let snapshot = try await CursorProvider(environment: world.environment).refresh()
        let rest = try #require(world.requests.first { $0.url.absoluteString == requestUsageURL })
        #expect(rest.headers["Cookie"] == "WorkosCursorSessionToken=user_01ABC%3A%3A\(token)")

        #expect(snapshot.windows.map(\.id) == ["requests"])
        #expect(abs(snapshot.windows[0].usedPercent - 62.4) < 0.01)
        #expect(snapshot.windows[0].resetsAt == DateParsing.iso8601("2026-09-11T00:00:00Z"))
        #expect(snapshot.note == nil)
        #expect(snapshot.extraUsage == ExtraUsage(isEnabled: false))
    }

    @Test("no meter anywhere leaves a connected snapshot with an explanatory note")
    func noMeter() async throws {
        let world = world(token: jwt(exp: Date(timeIntervalSince1970: 1_800_000_000)))
        world.respond(usageURL, fixture: "cursor-usage-enterprise.json")
        world.respondToEverything(HTTPResponse(statusCode: 404))

        let snapshot = try await CursorProvider(environment: world.environment).refresh()
        #expect(snapshot.status == .connected)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.note == "Cursor reports no included-usage meter for this plan.")
        #expect(snapshot.ringUsedPercent == nil)
    }

    @Test("a lapsed JWT or a 401 reads expired; no token reads absent")
    func credentialStates() async throws {
        let absent = try await CursorProvider(environment: TestWorld().environment).refresh()
        #expect(absent.status == .absent)

        let lapsed = world(token: jwt(exp: Date(timeIntervalSince1970: 1_700_000_000)))
        #expect(try await CursorProvider(environment: lapsed.environment).refresh().status == .expired)
        #expect(lapsed.requests.isEmpty)

        let rejected = world(token: jwt(exp: Date(timeIntervalSince1970: 1_800_000_000)))
        rejected.respond(usageURL, status: 401, json: #"{"code":"unauthenticated"}"#)
        #expect(try await CursorProvider(environment: rejected.environment).refresh().status == .expired)
    }

    @Test("5xx and 429 are retryable errors, not credential states")
    func transientErrors() async throws {
        let world = world(token: jwt(exp: Date(timeIntervalSince1970: 1_800_000_000)))
        world.respond(usageURL, status: 503, json: "{}")
        await #expect(throws: ProviderError.transient(statusCode: 503)) {
            _ = try await CursorProvider(environment: world.environment).refresh()
        }
    }

    @Test("a disabled account is connected with no windows and a note")
    func disabled() async throws {
        let world = world(token: jwt(exp: Date(timeIntervalSince1970: 1_800_000_000)))
        world.respond(usageURL, json: #"{"enabled":false}"#)
        world.respondToEverything(HTTPResponse(statusCode: 404))
        let snapshot = try await CursorProvider(environment: world.environment).refresh()
        #expect(snapshot.status == .connected)
        #expect(snapshot.note == "No active Cursor subscription — nothing to meter.")
    }
}
