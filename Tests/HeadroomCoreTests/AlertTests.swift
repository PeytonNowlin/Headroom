import Foundation
import HeadroomCore
import Testing

private let reset = Date(timeIntervalSince1970: 1_800_000_000)
private let week: TimeInterval = 7 * 86400

private func weekly(used: Double, resetsAt: Date = reset) -> QuotaWindow {
    QuotaWindow(id: "weekly", title: "Weekly", usedPercent: used, resetsAt: resetsAt, duration: week)
}

@Suite("Pace")
struct PaceTests {
    @Test("no projection until 10% of the window has elapsed, or without timing data")
    func gating() {
        let opened = reset.addingTimeInterval(-week)
        #expect(Pace.project(weekly(used: 50), now: opened.addingTimeInterval(week * 0.05)) == nil)
        #expect(Pace.project(weekly(used: 50), now: opened.addingTimeInterval(week * 0.1)) != nil)
        #expect(Pace.project(QuotaWindow(id: "x", title: "X", usedPercent: 50, resetsAt: nil, duration: week), now: opened) == nil)
        #expect(Pace.project(QuotaWindow(id: "x", title: "X", usedPercent: 50, resetsAt: reset, duration: nil), now: opened) == nil)
        #expect(Pace.project(QuotaWindow(id: "x", title: "X", usedPercent: 0, resetsAt: nil, duration: week, isStarted: false), now: opened) == nil)
    }

    @Test("half the window used at half time is on pace; 60% at half time runs out 1.17 days early")
    func projection() {
        let half = reset.addingTimeInterval(-week / 2)
        #expect(Pace.project(weekly(used: 50), now: half) == .onPace(projectedUsedPercent: 100))
        #expect(Pace.project(weekly(used: 0), now: half) == .onPace(projectedUsedPercent: 0))

        guard case let .runsOut(early)? = Pace.project(weekly(used: 60), now: half) else {
            Issue.record("expected runsOut"); return
        }
        // Exhaustion at 3.5d * (100/60) = 5.83d after open → 1.17d before reset.
        #expect(abs(early - (week - (week / 2) * (100 / 60))) < 1)
        #expect(Pace.hint(.runsOut(early: early), now: half) == "runs out ~1d 4h early")
        #expect(Pace.hint(.onPace(projectedUsedPercent: 72.4), now: half) == "on pace · ~72% at reset")
    }
}

@Suite("Alerts")
struct AlertTests {
    private func snapshot(_ used: Double, resetsAt: Date = reset, at now: Date) -> Snapshot {
        Snapshot(provider: .claude, fetchedAt: now, status: .connected, windows: [weekly(used: used, resetsAt: resetsAt)])
    }

    @Test("80 then 95 fire once each; nothing re-fires within a cycle")
    func sequencing() {
        var ledger = AlertLedger()
        let now = reset.addingTimeInterval(-3600)  // near the end: pace won't trigger at these levels

        #expect(AlertEvaluator.evaluate(snapshot(50, at: now), now: now, ledger: &ledger).isEmpty)
        let first = AlertEvaluator.evaluate(snapshot(82, at: now), now: now, ledger: &ledger)
        #expect(first.map(\.kind) == [.threshold(80)])
        #expect(first[0].message.hasPrefix("Claude Weekly at 82% used"))
        #expect(AlertEvaluator.evaluate(snapshot(88, at: now), now: now, ledger: &ledger).isEmpty)

        let second = AlertEvaluator.evaluate(snapshot(96, at: now), now: now, ledger: &ledger)
        #expect(second.map(\.kind) == [.threshold(95)])
        #expect(AlertEvaluator.evaluate(snapshot(99, at: now), now: now, ledger: &ledger).isEmpty)

        // Jumping straight past both fires both, in order.
        var fresh = AlertLedger()
        #expect(AlertEvaluator.evaluate(snapshot(97, at: now), now: now, ledger: &fresh).map(\.kind) == [.threshold(80), .threshold(95)])
    }

    @Test("a new reset time re-arms the window")
    func rearm() {
        var ledger = AlertLedger()
        let now = reset.addingTimeInterval(-3600)
        #expect(AlertEvaluator.evaluate(snapshot(85, at: now), now: now, ledger: &ledger).count == 1)
        #expect(AlertEvaluator.evaluate(snapshot(85, at: now), now: now, ledger: &ledger).isEmpty)

        let nextReset = reset.addingTimeInterval(week)
        let later = reset.addingTimeInterval(week - 3600)
        #expect(AlertEvaluator.evaluate(snapshot(85, resetsAt: nextReset, at: later), now: later, ledger: &ledger).count == 1)
        #expect(ledger.fired.count == 1)  // old cycle pruned
    }

    @Test("pace exhaustion fires once, and only when projected before reset")
    func pace() {
        var ledger = AlertLedger()
        let half = reset.addingTimeInterval(-week / 2)
        #expect(AlertEvaluator.evaluate(snapshot(40, at: half), now: half, ledger: &ledger).isEmpty)
        let alerts = AlertEvaluator.evaluate(snapshot(60, at: half), now: half, ledger: &ledger)
        #expect(alerts.map(\.kind) == [.paceExhaustion])
        #expect(alerts[0].message.contains("run out ~1d 4h early"))
        #expect(AlertEvaluator.evaluate(snapshot(65, at: half), now: half, ledger: &ledger).isEmpty)
    }

    @Test("expired and absent snapshots never alert")
    func statuses() {
        var ledger = AlertLedger()
        let now = reset.addingTimeInterval(-3600)
        var s = snapshot(99, at: now)
        s.status = .expired
        #expect(AlertEvaluator.evaluate(s, now: now, ledger: &ledger).isEmpty)
        #expect(AlertEvaluator.evaluate(.absent(.claude, at: now), now: now, ledger: &ledger).isEmpty)
    }
}
