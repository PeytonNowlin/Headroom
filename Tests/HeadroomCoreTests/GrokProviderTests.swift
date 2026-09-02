import Foundation
import HeadroomCore
import Testing

private let billingURL = "https://cli-chat-proxy.grok.com/v1/billing?format=credits"
private let settingsURL = "https://cli-chat-proxy.grok.com/v1/settings"
private let noPersonalTeam = #"{"code":"The system is not in a state required for the operation's execution","error":"No personal team."}"#

private func authJSON(key: String, expiresAt: String? = nil, team: Bool = false) -> String {
    let expires = expiresAt.map { "\"expires_at\":\"\($0)\"," } ?? ""
    let principal = team ? #""principal_type":"Team","team_id":"team_1","team_name":"Acme","# : #""principal_type":"User","#
    return """
    {"https://auth.x.ai::client-abc":{"auth_mode":"oauth","key":"\(key)","refresh_token":"rt",\(expires)\(principal)"user_id":"u1","email":"redacted@example.com"}}
    """
}

@Suite("Grok provider")
struct GrokProviderTests {
    @Test("reads the keyed auth entry, sends the CLI auth header, maps the weekly pool and cap")
    func weeklyPool() async throws {
        let world = TestWorld()
        world.file(".grok/auth.json", authJSON(key: "gk"))
        world.respond(settingsURL, fixture: "grok-settings.json")
        world.respond(billingURL, fixture: "grok-billing-weekly.json")

        let snapshot = try await GrokProvider(environment: world.environment).refresh()

        let billing = world.requests.first { $0.url.absoluteString == billingURL }
        #expect(billing?.headers["Authorization"] == "Bearer gk")
        #expect(billing?.headers["X-XAI-Token-Auth"] == "xai-grok-cli")
        #expect(snapshot.status == .connected)
        #expect(snapshot.planName == "SuperGrok")
        #expect(snapshot.windows.map(\.id) == ["weekly"])
        #expect(snapshot.windows[0].usedPercent == 42.5)
        #expect(snapshot.windows[0].resetsAt == DateParsing.iso8601("2026-09-04T04:01:09.238389+00:00"))
        #expect(snapshot.windows[0].duration == 604_800.0)
        #expect(snapshot.extraUsage == ExtraUsage(isEnabled: true, label: "2500 cap"))
        #expect(snapshot.ringUsedPercent == 42.5)
    }

    @Test("a team login has no personal billing: connected with plan and a note, no ring value")
    func teamAccount() async throws {
        let world = TestWorld()
        world.file(".grok/auth.json", authJSON(key: "gk", team: true))
        world.respond(settingsURL, fixture: "grok-settings.json")
        world.respond(billingURL, status: 412, json: noPersonalTeam)

        let snapshot = try await GrokProvider(environment: world.environment).refresh()
        #expect(snapshot.status == .connected)
        #expect(snapshot.planName == "SuperGrok")
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.ringUsedPercent == nil)
        #expect(snapshot.extraUsage == nil)
        #expect(snapshot.note?.contains("team") == true)
    }

    @Test("a monthly period yields no weekly window; absent percent means zero; no cap is Disabled")
    func monthlyAndDefaults() async throws {
        let world = TestWorld()
        world.file(".grok/auth.json", authJSON(key: "gk"))
        world.respond(settingsURL, fixture: "grok-settings.json")
        world.respond(billingURL, fixture: "grok-billing-monthly-zero.json")
        let snapshot = try await GrokProvider(environment: world.environment).refresh()
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.extraUsage == ExtraUsage(isEnabled: false, label: "Disabled"))

        let zero = TestWorld()
        zero.file(".grok/auth.json", authJSON(key: "gk"))
        zero.respond(settingsURL, status: 500, json: "{}")
        zero.respond(billingURL, json: #"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-28T00:00:00Z","end":"2026-09-04T00:00:00Z"}}}"#)
        let s = try await GrokProvider(environment: zero.environment).refresh()
        #expect(s.windows[0].usedPercent == 0)
        #expect(s.planName == nil)
        #expect(s.status == .connected)
    }

    @Test("other 412s are transient, 401 is expired, missing file is absent, GROK_HOME honored")
    func statuses() async throws {
        let other412 = TestWorld()
        other412.file(".grok/auth.json", authJSON(key: "gk"))
        other412.respond(settingsURL, fixture: "grok-settings.json")
        other412.respond(billingURL, status: 412, json: #"{"error":"Something else"}"#)
        await #expect(throws: ProviderError.transient(statusCode: 412)) {
            try await GrokProvider(environment: other412.environment).refresh()
        }

        let rejected = TestWorld()
        rejected.file(".grok/auth.json", authJSON(key: "gk"))
        rejected.respond(settingsURL, status: 401, json: "{}")
        rejected.respond(billingURL, status: 401, json: "{}")
        #expect(try await GrokProvider(environment: rejected.environment).refresh().status == .expired)

        let none = TestWorld()
        #expect(GrokProvider(environment: none.environment).hasLocalCredentials() == false)
        #expect(try await GrokProvider(environment: none.environment).refresh().status == .absent)

        let relocated = TestWorld()
        relocated.env("GROK_HOME", "/Users/test/alt-grok")
        relocated.absoluteFile("/Users/test/alt-grok/auth.json", authJSON(key: "alt"))
        relocated.respond(settingsURL, fixture: "grok-settings.json")
        relocated.respond(billingURL, fixture: "grok-billing-weekly.json")
        let ok = try await GrokProvider(environment: relocated.environment).refresh()
        #expect(ok.status == .connected)
        #expect(relocated.requests[0].headers["Authorization"] == "Bearer alt")
    }

    @Test("a key past its own expires_at is expired without a network call")
    func selfExpiry() async throws {
        let world = TestWorld()
        world.file(".grok/auth.json", authJSON(key: "gk", expiresAt: "2020-01-01T00:00:00Z"))
        let snapshot = try await GrokProvider(environment: world.environment).refresh()
        #expect(snapshot.status == .expired)
        #expect(world.requests.isEmpty)
    }
}
