import Foundation
import HeadroomCore
import Testing

@Suite("Compact reset cue")
struct QuotaRecoveryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func snapshot(used: Double, reset: Date?, fetched: Date, started: Bool = true) -> Snapshot {
        Snapshot(provider: .claude, fetchedAt: fetched, status: .connected,
                 windows: [QuotaWindow(id: "session", title: "Session", usedPercent: used, resetsAt: reset,
                                       duration: 18000, isStarted: started)])
    }
    @Test func confirmedResetAndIdleRecovery() {
        let old = snapshot(used: 50, reset: now.addingTimeInterval(-60), fetched: now.addingTimeInterval(-300))
        let fresh = snapshot(used: 2, reset: now.addingTimeInterval(18000), fetched: now)
        #expect(QuotaRecovery.confirmed(fresh, after: old, now: now))
        let idle = snapshot(used: 0, reset: nil, fetched: now, started: false)
        #expect(QuotaRecovery.confirmed(idle, after: old, now: now))
        #expect(!QuotaRecovery.confirmed(fresh, after: fresh, now: now))
        #expect(!QuotaRecovery.confirmed(fresh, after: nil, now: now))
    }
    @Test func suppressCorrectionsStaleAndFutureData() {
        let reset = now.addingTimeInterval(60)
        let old = snapshot(used: 80, reset: reset, fetched: now.addingTimeInterval(-300))
        let correction = snapshot(used: 10, reset: reset, fetched: now)
        #expect(!QuotaRecovery.confirmed(correction, after: old, now: now))
        let earlyReset = snapshot(used: 10, reset: now.addingTimeInterval(18000), fetched: now)
        #expect(!QuotaRecovery.confirmed(earlyReset, after: old, now: now))
        let stale = snapshot(used: 80, reset: now.addingTimeInterval(-60), fetched: now.addingTimeInterval(-1800))
        #expect(!QuotaRecovery.confirmed(earlyReset, after: stale, now: now))
        #expect(!QuotaRecovery.confirmed(earlyReset, after: old, now: now.addingTimeInterval(-1)))
    }
    @Test func unchangedLimitingWindowDoesNotSignalMoreHeadroom() {
        var old = snapshot(used: 80, reset: now.addingTimeInterval(-60), fetched: now.addingTimeInterval(-300))
        var fresh = snapshot(used: 0, reset: now.addingTimeInterval(18000), fetched: now)
        let weekly = QuotaWindow(id: "weekly", title: "Weekly", usedPercent: 90, resetsAt: now.addingTimeInterval(86400), duration: 7 * 86400)
        old.windows.append(weekly)
        fresh.windows.append(weekly)
        #expect(!QuotaRecovery.confirmed(fresh, after: old, now: now))
    }
}
