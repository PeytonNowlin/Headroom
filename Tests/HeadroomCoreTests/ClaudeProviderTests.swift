import Foundation
import HeadroomCore
import Testing

private let usageURL = "https://api.anthropic.com/api/oauth/usage"

private func keychainJSON(token: String, expiresAt: Date? = nil, plan: String = "max") -> String {
    let expires = expiresAt.map { "\(Int($0.timeIntervalSince1970 * 1000))" } ?? "null"
    return """
    {"claudeAiOauth":{"accessToken":"\(token)","refreshToken":"rt","expiresAt":\(expires),"scopes":["user:inference","user:profile"],"subscriptionType":"\(plan)","rateLimitTier":"default_claude_max_5x"}}
    """
}

@Suite("Claude provider")
struct ClaudeProviderTests {
    @Test("keychain login is preferred over the credentials file and env var")
    func keychainFirst() async throws {
        let world = TestWorld()
        world.keychain("Claude Code-credentials", keychainJSON(token: "kc-token"))
        world.file(".claude/.credentials.json", keychainJSON(token: "file-token"))
        world.env("CLAUDE_CODE_OAUTH_TOKEN", "env-token")
        world.respond(usageURL, fixture: "claude-usage.json")

        let snapshot = try await ClaudeProvider(environment: world.environment).refresh()

        #expect(world.requests.count == 1)
        #expect(world.requests[0].headers["Authorization"] == "Bearer kc-token")
        #expect(snapshot.status == .connected)
        #expect(snapshot.planName == "Max")
        #expect(snapshot.windows.map(\.id) == ["session", "weekly", "weekly:Fable"])
    }

    @Test("falls back to the credentials file, honoring CLAUDE_CONFIG_DIR, then the env var")
    func fallbackOrder() async throws {
        let world = TestWorld()
        world.env("CLAUDE_CONFIG_DIR", "/Users/test/custom-claude")
        world.absoluteFile("/Users/test/custom-claude/.credentials.json", keychainJSON(token: "file-token", plan: "pro"))
        world.env("CLAUDE_CODE_OAUTH_TOKEN", "env-token")
        world.respond(usageURL, fixture: "claude-usage.json")

        let fromFile = try await ClaudeProvider(environment: world.environment).refresh()
        #expect(world.requests.last?.headers["Authorization"] == "Bearer file-token")
        #expect(fromFile.planName == "Pro")

        let envOnly = TestWorld()
        envOnly.env("CLAUDE_CODE_OAUTH_TOKEN", "env-token")
        envOnly.respond(usageURL, fixture: "claude-usage.json")
        let fromEnv = try await ClaudeProvider(environment: envOnly.environment).refresh()
        #expect(envOnly.requests.last?.headers["Authorization"] == "Bearer env-token")
        #expect(fromEnv.status == .connected)
        #expect(fromEnv.planName == nil)
    }

    @Test("no credentials anywhere is absent and makes no network call")
    func absent() async throws {
        let world = TestWorld()
        let provider = ClaudeProvider(environment: world.environment)
        #expect(provider.hasLocalCredentials() == false)
        let snapshot = try await provider.refresh()
        #expect(snapshot.status == .absent)
        #expect(world.requests.isEmpty)
    }

    @Test("ring value is the most-used window, including model-scoped weekly limits")
    func ringUsesMostConstrainedWindow() async throws {
        let world = TestWorld()
        world.keychain("Claude Code-credentials", keychainJSON(token: "t"))
        world.respond(usageURL, fixture: "claude-usage.json")
        let normal = try await ClaudeProvider(environment: world.environment).refresh()
        #expect(normal.ringUsedPercent == 7)
        #expect(normal.ringRemainingPercent == 93)

        let hot = TestWorld()
        hot.keychain("Claude Code-credentials", keychainJSON(token: "t"))
        hot.respond(usageURL, fixture: "claude-usage-fable-high.json")
        let scoped = try await ClaudeProvider(environment: hot.environment).refresh()
        #expect(scoped.ringUsedPercent == 62)
        #expect(scoped.windows.first { $0.id == "weekly:Fable" }?.usedPercent == 62)
        #expect(scoped.windows.first { $0.id == "weekly:Sonnet" }?.title == "Sonnet")
    }

    @Test("a token the API rejects is reported expired, not thrown")
    func rejectedTokenIsExpired() async throws {
        let world = TestWorld()
        world.keychain("Claude Code-credentials", keychainJSON(token: "old"))
        world.respond(usageURL, status: 401, json: #"{"error":"unauthorized"}"#)
        let snapshot = try await ClaudeProvider(environment: world.environment).refresh()
        #expect(snapshot.status == .expired)
        #expect(snapshot.planName == "Max")
    }

    @Test("a credential past its own expiry is skipped in favor of the next source")
    func selfDeclaredExpiryIsSkipped() async throws {
        let world = TestWorld()
        world.keychain("Claude Code-credentials", keychainJSON(token: "stale", expiresAt: world.now.addingTimeInterval(-60)))
        world.file(".claude/.credentials.json", keychainJSON(token: "fresh", expiresAt: world.now.addingTimeInterval(3600)))
        world.respond(usageURL, fixture: "claude-usage.json")
        let snapshot = try await ClaudeProvider(environment: world.environment).refresh()
        #expect(world.requests[0].headers["Authorization"] == "Bearer fresh")
        #expect(snapshot.status == .connected)

        let allStale = TestWorld()
        allStale.keychain("Claude Code-credentials", keychainJSON(token: "stale", expiresAt: allStale.now.addingTimeInterval(-60)))
        let expired = try await ClaudeProvider(environment: allStale.environment).refresh()
        #expect(expired.status == .expired)
        #expect(allStale.requests.isEmpty)
    }

    @Test("server errors are transient and surface as thrown errors for the poller")
    func serverErrorIsTransient() async {
        let world = TestWorld()
        world.keychain("Claude Code-credentials", keychainJSON(token: "t"))
        world.respond(usageURL, status: 503, json: "{}")
        await #expect(throws: ProviderError.transient(statusCode: 503)) {
            try await ClaudeProvider(environment: world.environment).refresh()
        }
    }

    @Test("session window with no reset time is not started; extra usage maps to dollars")
    func windowDetails() async throws {
        let world = TestWorld()
        world.keychain("Claude Code-credentials", keychainJSON(token: "t"))
        world.respond(usageURL, json: """
        {"limits":[{"kind":"session","percent":0,"resets_at":null},{"kind":"weekly_all","percent":4,"resets_at":"2026-09-05T09:00:00+00:00"}],
         "extra_usage":{"is_enabled":true,"monthly_limit":5000,"used_credits":320.0,"decimal_places":2}}
        """)
        let snapshot = try await ClaudeProvider(environment: world.environment).refresh()
        let session = snapshot.windows.first { $0.id == "session" }
        #expect(session?.isStarted == false)
        #expect(session?.resetsAt == nil)
        #expect(snapshot.windows.first { $0.id == "weekly" }?.resetsAt == DateParsing.iso8601("2026-09-05T09:00:00+00:00"))
        #expect(snapshot.extraUsage == ExtraUsage(isEnabled: true, usedDollars: 3.2, limitDollars: 50))
    }
}
