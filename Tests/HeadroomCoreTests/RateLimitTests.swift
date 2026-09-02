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

    @Test("a rate-limited provider waits at least ten minutes and stays credentialed with no snapshot")
    func backoff() async throws {
        let world = TestWorld()
        world.file(".claude/.credentials.json", #"{"claudeAiOauth":{"accessToken":"t","expiresAt":9999999999999}}"#)
        world.respondToEverything(HTTPResponse(statusCode: 429))
        let poller = ProviderPoller(runtime: ClaudeProvider(environment: world.environment), environment: world.environment)

        let state = await poller.refreshOnce()
        #expect(state.snapshot == nil)
        #expect(state.hasCredentials)
        #expect(state.isErrored)
        #expect(state.lastError == "Rate limited")

        await poller.start()
        try await Task.sleep(for: .milliseconds(50))
        await poller.stop()
        #expect(world.sleeps.first.map { $0.seconds >= 600 } == true)
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
