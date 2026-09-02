import Foundation

/// Linear burn-rate projection for a quota window.
public enum Pace {
    public enum Projection: Equatable, Sendable {
        /// Projected to end the window at or under 100%.
        case onPace(projectedUsedPercent: Double)
        /// Projected to hit 100% this much before the reset.
        case runsOut(early: TimeInterval)
    }

    /// Don't project until this fraction of the window has elapsed; early samples are noise.
    public static let minimumElapsedFraction = 0.1

    public static func project(_ window: QuotaWindow, now: Date) -> Projection? {
        guard window.isStarted, let resets = window.resetsAt, let duration = window.duration, duration > 0 else { return nil }
        let opened = resets.addingTimeInterval(-duration)
        let elapsed = now.timeIntervalSince(opened)
        guard elapsed > 0, resets > now else { return nil }
        let fraction = elapsed / duration
        guard fraction >= minimumElapsedFraction else { return nil }

        let used = max(0, window.usedPercent)
        guard used > 0 else { return .onPace(projectedUsedPercent: 0) }
        let projectedAtReset = used / fraction
        if projectedAtReset <= 100 {
            return .onPace(projectedUsedPercent: projectedAtReset)
        }
        let secondsToExhaust = elapsed * (100 / used)
        let exhaustion = opened.addingTimeInterval(secondsToExhaust)
        return .runsOut(early: max(0, resets.timeIntervalSince(exhaustion)))
    }

    public static func hint(_ projection: Projection, now: Date) -> String {
        switch projection {
        case let .onPace(p):
            return p < 1 ? "on pace" : "on pace · ~\(Int(p.rounded()))% at reset"
        case let .runsOut(early):
            return "runs out ~\(Formatting.countdown(to: now.addingTimeInterval(early), from: now)) early"
        }
    }
}
