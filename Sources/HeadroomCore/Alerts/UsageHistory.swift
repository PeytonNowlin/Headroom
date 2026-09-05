import Foundation

/// Only quota percentages and timestamps are stored, never prompts or credentials.
/// Retain at most one hour per current window, sufficient for a recent burn rate.
public struct UsageHistory: Codable, Sendable, Equatable {
    public struct Sample: Codable, Sendable, Equatable {
        public var at: Date
        public var used: Double
    }

    private var samples: [String: [Sample]] = [:]
    public init() {}

    public mutating func record(_ snapshot: Snapshot) {
        guard snapshot.status == .connected else { return }
        let latest = samples.filter { $0.key.hasPrefix(snapshot.provider.rawValue + "|") }
            .values.compactMap { $0.last?.at }.max()
        guard latest.map({ snapshot.fetchedAt > $0 }) ?? true else { return }
        let cutoff = snapshot.fetchedAt.addingTimeInterval(-3600)
        samples = samples.compactMapValues { values in
            let recent = values.filter { $0.at >= cutoff }
            return recent.isEmpty ? nil : recent
        }
        let live = Set(snapshot.windows.map { AlertLedger.cycleKey(snapshot.provider, $0) })
        samples = samples.filter { !$0.key.hasPrefix(snapshot.provider.rawValue + "|") || live.contains($0.key) }
        for window in snapshot.windows where window.isStarted && window.usedPercent.isFinite {
            let key = AlertLedger.cycleKey(snapshot.provider, window)
            var values = samples[key] ?? []
            if let last = values.last {
                guard snapshot.fetchedAt > last.at else { continue }
                // An unannounced reset or a polling gap starts a new observation period.
                if window.usedPercent < last.used || snapshot.fetchedAt.timeIntervalSince(last.at) > 15 * 60 {
                    values = []
                } else if snapshot.fetchedAt.timeIntervalSince(last.at) < 60 {
                    values.removeLast()
                }
            }
            values.append(Sample(at: snapshot.fetchedAt, used: max(0, min(100, window.usedPercent))))
            samples[key] = Array(values.suffix(61))
        }
    }

    public func recent(provider: ProviderID, window: QuotaWindow, now: Date) -> [Sample] {
        (samples[AlertLedger.cycleKey(provider, window)] ?? []).filter {
            $0.at <= now && now.timeIntervalSince($0.at) <= 3600
        }
    }
}

public extension Pace {
    struct Forecast: Equatable, Sendable {
        public var recent: Projection
        public var wholeWindow: Projection?
        public var observationDuration: TimeInterval
        /// Suppress pace warnings when a single burst dominates the observation period.
        public var isVariable: Bool

        public var warning: Projection? { isVariable ? nil : recent }
    }

    static func forecast(_ window: QuotaWindow, provider: ProviderID, history: UsageHistory, now: Date) -> Forecast? {
        guard window.isStarted, let reset = window.resetsAt, reset > now,
              window.usedPercent.isFinite, window.remainingPercent > 0 else { return nil }
        let values = history.recent(provider: provider, window: window, now: now)
        guard values.count >= 3, let first = values.first, let last = values.last,
              now.timeIntervalSince(last.at) <= 10 * 60,
              last.at.timeIntervalSince(first.at) >= 10 * 60 else { return nil }
        let elapsed = last.at.timeIntervalSince(first.at)
        let rate = (last.used - first.used) / elapsed
        guard rate >= 0 else { return nil }
        let intervals = zip(values, values.dropFirst()).map { earlier, later in
            (later.used - earlier.used) / later.at.timeIntervalSince(earlier.at)
        }
        let variable = rate > 0 && (intervals.max() ?? 0) > rate * 1.8
        // Anchor at the actual observation, not the UI clock: idle ticks cannot move exhaustion.
        let remainingTime = reset.timeIntervalSince(last.at)
        let projected = last.used + rate * remainingTime
        let recent: Projection
        if projected > 100, rate > 0 {
            recent = .runsOut(early: max(0, remainingTime - (100 - last.used) / rate))
        } else {
            recent = .onPace(projectedUsedPercent: projected)
        }
        return Forecast(recent: recent, wholeWindow: project(window, now: last.at),
                        observationDuration: elapsed, isVariable: variable)
    }
}
