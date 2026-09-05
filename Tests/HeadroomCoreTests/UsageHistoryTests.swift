import Foundation
import HeadroomCore
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func usage(_ used: Double, at date: Date = now, reset: Date = now.addingTimeInterval(3600), provider: ProviderID = .claude) -> Snapshot {
    Snapshot(provider: provider, fetchedAt: date, status: .connected, windows: [
        QuotaWindow(id: "session", title: "Session", usedPercent: used, resetsAt: reset, duration: 5 * 3600),
    ])
}

private func history(_ points: [(TimeInterval, Double)]) -> UsageHistory {
    var history = UsageHistory()
    for (ago, used) in points { history.record(usage(used, at: now.addingTimeInterval(-ago))) }
    return history
}

@Suite("Recent quota forecasts")
struct UsageHistoryTests {
    @Test("requires three fresh observations spanning ten minutes")
    func confidence() {
        let window = usage(60).windows[0]
        for points: [(TimeInterval, Double)] in [[], [(0, 60)], [(600, 50), (0, 60)], [(120, 50), (60, 55), (0, 60)]] {
            #expect(Pace.forecast(window, provider: .claude, history: history(points), now: now) == nil)
        }
        let collected = history([(600, 50), (300, 55), (0, 60)])
        #expect(Pace.forecast(window, provider: .claude, history: collected, now: now) != nil)
        #expect(Pace.forecast(window, provider: .claude, history: collected, now: now.addingTimeInterval(601)) == nil)
        #expect(Pace.forecast(window, provider: .codex, history: collected, now: now) == nil)
    }

    @Test("recent acceleration differs from whole-window pace and stays anchored between polls")
    func acceleration() throws {
        let window = usage(60).windows[0]
        let collected = history([(600, 50), (300, 55), (0, 60)])
        let forecast = try #require(Pace.forecast(window, provider: .claude, history: collected, now: now))
        #expect(forecast.recent == .runsOut(early: 1200))
        #expect(forecast.wholeWindow == .onPace(projectedUsedPercent: 75))
        #expect(!forecast.isVariable)
        #expect(Pace.forecast(window, provider: .claude, history: collected, now: now.addingTimeInterval(60)) == forecast)
    }

    @Test("idle use is on pace; a single burst has no confident warning")
    func bursts() throws {
        let window = usage(60).windows[0]
        let idle = try #require(Pace.forecast(window, provider: .claude, history: history([(600, 60), (300, 60), (0, 60)]), now: now))
        #expect(idle.recent == .onPace(projectedUsedPercent: 60))
        let burst = try #require(Pace.forecast(window, provider: .claude, history: history([(600, 50), (300, 60), (0, 60)]), now: now))
        #expect(burst.isVariable)
        #expect(burst.warning == nil)
    }

    @Test("reset changes, usage corrections, and long gaps require fresh observations")
    func discontinuities() {
        let original = history([(600, 50), (300, 55), (0, 60)])
        let later = now.addingTimeInterval(300)
        for snapshot in [usage(5, at: later), usage(65, at: later, reset: now.addingTimeInterval(7200)), usage(65, at: now.addingTimeInterval(901))] {
            var collected = original
            collected.record(snapshot)
            #expect(Pace.forecast(snapshot.windows[0], provider: .claude, history: collected, now: snapshot.fetchedAt) == nil)
        }
    }

    @Test("history persists, is bounded, ignores old samples, and isolates providers")
    func retention() throws {
        var collected = UsageHistory()
        for i in 0...120 {
            collected.record(usage(Double(i) / 2, at: now.addingTimeInterval(Double(i - 120) * 60)))
        }
        let window = usage(60).windows[0]
        #expect(collected.recent(provider: .claude, window: window, now: now).count == 61)
        collected.record(usage(1, at: now.addingTimeInterval(-7200)))
        collected.record(usage(20, provider: .codex))
        #expect(collected.recent(provider: .claude, window: window, now: now).count == 61)
        #expect(collected.recent(provider: .codex, window: window, now: now).count == 1)
        let restored = try JSONDecoder().decode(UsageHistory.self, from: JSONEncoder().encode(collected))
        #expect(restored == collected)
    }

    @Test("rapid manual refreshes preserve the latest observation without unbounded samples")
    func manualRefresh() {
        var collected = history([(600, 50), (300, 55), (0, 60)])
        for i in 1...30 { collected.record(usage(60 + Double(i) / 30, at: now.addingTimeInterval(Double(i)))) }
        let values = collected.recent(provider: .claude, window: usage(61).windows[0], now: now.addingTimeInterval(30))
        #expect(values.count == 3)
        #expect(values.last?.used == 61)
    }

    @Test("expired snapshots and exhausted or elapsed windows cannot produce forecasts")
    func invalidStates() {
        var collected = history([(600, 50), (300, 55), (0, 60)])
        let before = collected
        collected.record(.expired(.claude, at: now.addingTimeInterval(300)))
        #expect(collected == before)
        #expect(Pace.forecast(usage(100).windows[0], provider: .claude, history: collected, now: now) == nil)
        #expect(Pace.forecast(usage(60).windows[0], provider: .claude, history: collected, now: now.addingTimeInterval(3600)) == nil)
    }
}

@Suite("Alert controls")
struct AlertControlTests {
    @Test("threshold and pace warnings coalesce and remain deduplicated after restart")
    func coalescing() throws {
        let snapshot = usage(96)
        let forecast = try #require(Pace.forecast(snapshot.windows[0], provider: .claude,
                                               history: history([(600, 90), (300, 93), (0, 96)]), now: now))
        var ledger = AlertLedger()
        let alerts = AlertEvaluator.evaluate(snapshot, now: now, ledger: &ledger, forecasts: ["session": forecast])
        #expect(alerts.count == 1)
        let alert = try #require(alerts.first)
        #expect(alert.kind == .threshold(95))
        #expect(alert.message.contains("recent pace"))
        var restored = try JSONDecoder().decode(AlertLedger.self, from: JSONEncoder().encode(ledger))
        #expect(AlertEvaluator.evaluate(snapshot, now: now, ledger: &restored, forecasts: ["session": forecast]).isEmpty)
    }

    @Test("warnings can be disabled per provider or snoozed through a reset cycle")
    func suppression() throws {
        let snapshot = usage(96)
        var options = AlertOptions()
        var ledger = AlertLedger()
        options.warningsEnabled = false
        #expect(AlertEvaluator.evaluate(snapshot, now: now, ledger: &ledger, options: options).isEmpty)
        options.warningsEnabled = true
        options.snooze(snapshot)
        options = try JSONDecoder().decode(AlertOptions.self, from: JSONEncoder().encode(options))
        #expect(AlertEvaluator.evaluate(snapshot, now: now, ledger: &ledger, options: options).isEmpty)
        #expect(AlertEvaluator.evaluate(usage(96, provider: .codex), now: now, ledger: &ledger, options: options).count == 1)
        let next = usage(96, reset: now.addingTimeInterval(7200))
        #expect(AlertEvaluator.evaluate(next, now: now, ledger: &ledger, options: options).count == 1)
    }

    @Test("quota-return banners are opt-in, confirmed, and once per new cycle")
    func returns() {
        let before = usage(100, at: now.addingTimeInterval(-300), reset: now.addingTimeInterval(-1))
        let after = usage(5)
        var ledger = AlertLedger()
        #expect(AlertEvaluator.evaluate(after, now: now, ledger: &ledger, previous: before).isEmpty)
        var options = AlertOptions()
        options.warningsEnabled = false
        options.notifyOnReset = true
        options.snooze(before)
        #expect(AlertEvaluator.evaluate(after, now: now, ledger: &ledger, previous: before, options: options).map(\.kind) == [.quotaReturned])
        #expect(AlertEvaluator.evaluate(after, now: now, ledger: &ledger, previous: before, options: options).isEmpty)
        var fresh = AlertLedger()
        #expect(AlertEvaluator.evaluate(after, now: now, ledger: &fresh, previous: usage(70, at: now.addingTimeInterval(-300)), options: options).isEmpty)
        #expect(AlertEvaluator.evaluate(after, now: now, ledger: &fresh, previous: usage(100, at: now.addingTimeInterval(-300)), options: options).isEmpty)
        #expect(AlertEvaluator.evaluate(after, now: now, ledger: &fresh, options: options).isEmpty)
    }

    @Test("an exhausted Claude session recovers while idle, once across restart and first use")
    func idleRecovery() throws {
        let before = usage(100, at: now.addingTimeInterval(-300), reset: now.addingTimeInterval(-1))
        var idle = usage(0)
        idle.windows[0].resetsAt = nil
        idle.windows[0].isStarted = false
        var options = AlertOptions()
        options.notifyOnReset = true
        var ledger = AlertLedger()
        let alerts = AlertEvaluator.evaluate(idle, now: now, ledger: &ledger, previous: before, options: options)
        #expect(alerts.map(\.kind) == [.quotaReturned])
        #expect(alerts.first?.resetsAt == nil)
        var restored = try JSONDecoder().decode(AlertLedger.self, from: JSONEncoder().encode(ledger))
        #expect(AlertEvaluator.evaluate(idle, now: now, ledger: &restored, previous: before, options: options).isEmpty)
        var laterIdle = idle
        laterIdle.fetchedAt = now.addingTimeInterval(300)
        #expect(AlertEvaluator.evaluate(laterIdle, now: laterIdle.fetchedAt, ledger: &restored, previous: idle, options: options).isEmpty)
        let started = usage(5, at: now.addingTimeInterval(600))
        #expect(AlertEvaluator.evaluate(started, now: started.fetchedAt, ledger: &restored, previous: laterIdle, options: options).isEmpty)
    }

    @Test("idle recovery requires a fresh zero-usage response after the known reset")
    func idleRecoveryConfirmation() {
        var idle = usage(0)
        idle.windows[0].resetsAt = nil
        idle.windows[0].isStarted = false
        var options = AlertOptions()
        options.notifyOnReset = true
        let futureReset = usage(100, at: now.addingTimeInterval(-300), reset: now.addingTimeInterval(1))
        var ledger = AlertLedger()
        #expect(AlertEvaluator.evaluate(idle, now: now, ledger: &ledger, previous: futureReset, options: options).isEmpty)
        // UI time passing cannot turn a pre-reset observation into confirmed recovery.
        #expect(AlertEvaluator.evaluate(idle, now: now.addingTimeInterval(2), ledger: &ledger, previous: futureReset, options: options).isEmpty)
        let before = usage(100, at: now.addingTimeInterval(-300), reset: now.addingTimeInterval(-1))
        var nonzero = idle
        nonzero.windows[0].usedPercent = 1
        #expect(AlertEvaluator.evaluate(nonzero, now: now, ledger: &ledger, previous: before, options: options).isEmpty)
        var stale = idle
        stale.status = .stale
        #expect(AlertEvaluator.evaluate(stale, now: now, ledger: &ledger, previous: before, options: options).isEmpty)
    }

    @Test("stale and elapsed snapshots cannot emit warnings or recovery alerts")
    func stale() {
        var ledger = AlertLedger()
        var snapshot = usage(96)
        snapshot.status = .stale
        #expect(AlertEvaluator.evaluate(snapshot, now: now, ledger: &ledger).isEmpty)
        #expect(AlertEvaluator.evaluate(usage(96, at: now.addingTimeInterval(-601)), now: now, ledger: &ledger).isEmpty)
        #expect(AlertEvaluator.evaluate(usage(96, reset: now.addingTimeInterval(-1)), now: now, ledger: &ledger).isEmpty)
    }
}

@Suite("Readable quota status")
struct QuotaStatusTests {
    @Test("saved data, offline failures, cooldowns, and missing logins are explicit")
    func freshness() {
        var state = ProviderState(provider: .claude, snapshot: usage(50), isRestored: true)
        #expect(state.status(at: now) == .stale)
        #expect(state.freshness(at: now).contains("Saved usage"))
        state.lastError = "Network unavailable"
        #expect(state.freshness(at: now) == "Refresh failed · showing saved usage")
        state.rateLimitedUntil = now.addingTimeInterval(60)
        #expect(state.freshness(at: now) == "Rate limited · showing saved usage")
        #expect(ProviderState(provider: .claude).freshness(at: now) == "Not signed in")
        state.snapshot = .expired(.claude, at: now)
        #expect(state.freshness(at: now) == "Login expired")
    }

    @Test("limiting window matches the ring and ignores invalid percentages")
    func limiting() {
        var snapshot = usage(30)
        snapshot.windows.append(QuotaWindow(id: "weekly", title: "Weekly", usedPercent: 85, resetsAt: nil, duration: nil))
        snapshot.windows.append(QuotaWindow(id: "bad", title: "Bad", usedPercent: .nan, resetsAt: nil, duration: nil))
        #expect(snapshot.limitingWindow?.id == "weekly")
        #expect(snapshot.ringRemainingPercent == 15)
    }
}
