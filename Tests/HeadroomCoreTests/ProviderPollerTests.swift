import Foundation
import HeadroomCore
import Testing

private let usageURL = "https://api.anthropic.com/api/oauth/usage"
private let credential = """
{"claudeAiOauth":{"accessToken":"t","subscriptionType":"max"}}
"""

@Suite("Provider poller")
struct ProviderPollerTests {
    @Test("back-off doubles from the base and caps at the maximum")
    func backoffProgression() {
        let policy = BackoffPolicy(base: .seconds(60), maximum: .seconds(900))
        #expect(policy.delay(afterFailures: 1) == .seconds(60))
        #expect(policy.delay(afterFailures: 2) == .seconds(120))
        #expect(policy.delay(afterFailures: 3) == .seconds(240))
        #expect(policy.delay(afterFailures: 4) == .seconds(480))
        #expect(policy.delay(afterFailures: 5) == .seconds(900))
        #expect(policy.delay(afterFailures: 9) == .seconds(900))
    }

    @Test("failures keep the last good snapshot and a success resets the failure count")
    func retainsSnapshotAcrossFailures() async throws {
        let world = TestWorld()
        world.keychain("Claude Code-credentials", credential)
        world.respond(usageURL, fixture: "claude-usage.json")
        world.respond(usageURL, status: 500, json: "{}")
        world.respond(usageURL, status: 502, json: "{}")
        world.respond(usageURL, fixture: "claude-usage-fable-high.json")

        let poller = ProviderPoller(runtime: ClaudeProvider(environment: world.environment), environment: world.environment)

        let first = await poller.refreshOnce()
        #expect(first.snapshot?.ringUsedPercent == 7)
        #expect(first.consecutiveFailures == 0)

        let afterOneFailure = await poller.refreshOnce()
        #expect(afterOneFailure.snapshot?.ringUsedPercent == 7)
        #expect(afterOneFailure.consecutiveFailures == 1)
        #expect(afterOneFailure.lastError == "HTTP 500")

        let afterTwo = await poller.refreshOnce()
        #expect(afterTwo.snapshot?.ringUsedPercent == 7)
        #expect(afterTwo.consecutiveFailures == 2)

        let recovered = await poller.refreshOnce()
        #expect(recovered.snapshot?.ringUsedPercent == 62)
        #expect(recovered.consecutiveFailures == 0)
        #expect(recovered.lastError == nil)
    }

    @Test("the loop waits the interval after success and backs off after failures")
    func loopSchedulesDelays() async throws {
        let world = TestWorld()
        world.keychain("Claude Code-credentials", credential)
        world.respond(usageURL, fixture: "claude-usage.json")
        world.respond(usageURL, status: 500, json: "{}")
        world.respond(usageURL, status: 500, json: "{}")
        world.respond(usageURL, status: 500, json: "{}")
        world.respond(usageURL, fixture: "claude-usage.json")

        let poller = ProviderPoller(
            runtime: ClaudeProvider(environment: world.environment),
            environment: world.environment,
            interval: .seconds(60),
            backoff: BackoffPolicy(base: .seconds(60), maximum: .seconds(900))
        )
        await poller.start()

        var completed = 0
        for await state in await poller.states where !state.isRefreshing {
            completed += 1
            if completed == 5 { break }
        }
        await poller.stop()

        #expect(Array(world.sleeps.prefix(4)).map(\.seconds) == [60, 60, 120, 240])
    }

    @Test("a snapshot reads connected for five minutes, then stale")
    func staleAfterFiveMinutes() {
        let fetched = Date(timeIntervalSince1970: 1_000_000)
        let state = ProviderState(
            provider: .claude,
            snapshot: Snapshot(provider: .claude, fetchedAt: fetched, status: .connected)
        )
        #expect(state.status(at: fetched.addingTimeInterval(299)) == .connected)
        #expect(state.status(at: fetched.addingTimeInterval(301)) == .stale)

        let expired = ProviderState(provider: .claude, snapshot: .expired(.claude, at: fetched))
        #expect(expired.status(at: fetched.addingTimeInterval(9999)) == .expired)
        #expect(ProviderState(provider: .claude).status(at: fetched) == .absent)
    }
}
