import Foundation
import HeadroomCore
import Testing

@Suite("Rate limiting")
struct RateLimitTests {
    @Test("429 maps to rateLimited with the Retry-After hint")
    func mapping() {
        #expect(ProviderError.fromResponse(HTTPResponse(statusCode: 429, headers: ["retry-after": "120"])) == .rateLimited(retryAfter: 120))
        #expect(ProviderError.fromResponse(HTTPResponse(statusCode: 429)) == .rateLimited(retryAfter: nil))
        #expect(ProviderError.fromResponse(HTTPResponse(statusCode: 503)) == .transient(statusCode: 503))
    }

    @Test("after a 429 the provider cools down until the next regular slot and ignores manual refresh")
    func cooldown() async throws {
        let world = TestWorld()
        world.file(".claude/.credentials.json", #"{"claudeAiOauth":{"accessToken":"t","expiresAt":9999999999999}}"#)
        world.respondToEverything(HTTPResponse(statusCode: 429))
        let poller = ProviderPoller(runtime: ClaudeProvider(environment: world.environment), environment: world.environment)

        let state = await poller.refreshOnce()
        #expect(state.snapshot == nil)
        #expect(state.hasCredentials)
        #expect(state.isErrored)
        #expect(state.lastError == "Rate limited")
        #expect(state.rateLimitedUntil == world.now.addingTimeInterval(300))
        #expect(state.isRateLimited(at: world.now))

        // A manual refresh during cooldown must not produce a request.
        let before = world.requests.count
        await poller.refreshNow()
        try await Task.sleep(for: .milliseconds(20))
        #expect(world.requests.count == before)

        // Retry-After longer than the slot wins.
        let slow = TestWorld()
        slow.file(".claude/.credentials.json", #"{"claudeAiOauth":{"accessToken":"t","expiresAt":9999999999999}}"#)
        slow.respondToEverything(HTTPResponse(statusCode: 429, headers: ["retry-after": "900"]))
        let s = await ProviderPoller(runtime: ClaudeProvider(environment: slow.environment), environment: slow.environment).refreshOnce()
        #expect(s.rateLimitedUntil == slow.now.addingTimeInterval(900))
    }

    @Test("a cooldown restored from disk is honored before the first request after relaunch")
    func restoredCooldown() async throws {
        let world = TestWorld()
        world.file(".claude/.credentials.json", #"{"claudeAiOauth":{"accessToken":"t","expiresAt":9999999999999}}"#)
        world.respondToEverything(HTTPResponse(statusCode: 200, body: Fixtures.data("claude-usage.json")))
        let poller = ProviderPoller(runtime: ClaudeProvider(environment: world.environment), environment: world.environment,
                                    rateLimitedUntil: world.now.addingTimeInterval(120))
        await poller.start()
        try await Task.sleep(for: .milliseconds(50))
        await poller.stop()
        // First wait is the remaining cooldown; only then does a request go out and the regular
        // cadence resume.
        #expect(world.sleeps.first == .seconds(120))
        #expect(world.sleeps.dropFirst().first == .seconds(300))
        #expect(!world.requests.isEmpty)
    }

    @Test("default cadence is five minutes and staleness is three missed polls")
    func cadence() async throws {
        let world = TestWorld()
        world.file(".claude/.credentials.json", #"{"claudeAiOauth":{"accessToken":"t","expiresAt":9999999999999}}"#)
        world.respondToEverything(HTTPResponse(statusCode: 200, body: Fixtures.data("claude-usage.json")))
        let poller = ProviderPoller(runtime: ClaudeProvider(environment: world.environment), environment: world.environment)
        await poller.start()
        try await Task.sleep(for: .milliseconds(50))
        await poller.stop()
        #expect(world.sleeps.first == .seconds(300))
        #expect(ProviderState.stalenessWindow == 900)
    }

    @Test("an initial snapshot is served immediately and shows as stale")
    func initialSnapshot() async throws {
        let world = TestWorld()
        let old = Snapshot(provider: .claude, fetchedAt: world.now.addingTimeInterval(-3600), status: .connected,
                           windows: [QuotaWindow(id: "session", title: "Session", usedPercent: 40, resetsAt: nil, duration: nil)])
        let poller = ProviderPoller(runtime: ClaudeProvider(environment: world.environment), environment: world.environment,
                                    initialSnapshot: old)
        let state = await poller.current
        #expect(state.snapshot == old)
        #expect(state.status(at: world.now) == .stale)
    }
}
