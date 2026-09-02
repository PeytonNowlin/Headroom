import Foundation

public struct UsageAlert: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable, Hashable {
        case threshold(Int)
        case paceExhaustion

        var ledgerKey: String {
            switch self {
            case let .threshold(p): "t\(p)"
            case .paceExhaustion: "pace"
            }
        }
    }

    public var provider: ProviderID
    public var windowID: String
    public var kind: Kind
    public var message: String
    public var firedAt: Date

    public var id: String { "\(provider.rawValue)|\(windowID)|\(kind.ledgerKey)|\(firedAt.timeIntervalSince1970)" }
}

/// Which alerts have fired for which reset cycle. Keyed on provider + window + reset time, so a
/// new reset re-arms everything automatically.
public struct AlertLedger: Codable, Equatable, Sendable {
    public var fired: [String: Set<String>] = [:]

    public init() {}

    static func cycleKey(_ provider: ProviderID, _ window: QuotaWindow) -> String {
        let reset = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        return "\(provider.rawValue)|\(window.id)|\(reset)"
    }

    /// Forget cycles the snapshot no longer reports.
    mutating func prune(keeping keys: Set<String>) {
        fired = fired.filter { keys.contains($0.key) }
    }
}

public enum AlertEvaluator {
    public static let thresholds = [80, 95]

    /// Pure: given the newest snapshot and the ledger, return alerts to show and update the ledger.
    public static func evaluate(_ snapshot: Snapshot, now: Date, ledger: inout AlertLedger) -> [UsageAlert] {
        guard snapshot.status == .connected || snapshot.status == .stale else { return [] }
        var alerts: [UsageAlert] = []
        var live: Set<String> = []

        for window in snapshot.windows {
            let key = AlertLedger.cycleKey(snapshot.provider, window)
            live.insert(key)
            var fired = ledger.fired[key] ?? []

            for threshold in thresholds where window.usedPercent >= Double(threshold) {
                let kind = UsageAlert.Kind.threshold(threshold)
                guard !fired.contains(kind.ledgerKey) else { continue }
                fired.insert(kind.ledgerKey)
                let resetText = window.resetsAt.map { " · resets in \(Formatting.countdown(to: $0, from: now))" } ?? ""
                alerts.append(UsageAlert(
                    provider: snapshot.provider, windowID: window.id, kind: kind,
                    message: "\(snapshot.provider.displayName) \(window.title) at \(Int(window.usedPercent.rounded()))% used\(resetText)",
                    firedAt: now
                ))
            }

            if case let .runsOut(early)? = Pace.project(window, now: now), early > 0,
               !fired.contains(UsageAlert.Kind.paceExhaustion.ledgerKey) {
                fired.insert(UsageAlert.Kind.paceExhaustion.ledgerKey)
                alerts.append(UsageAlert(
                    provider: snapshot.provider, windowID: window.id, kind: .paceExhaustion,
                    message: "\(snapshot.provider.displayName) \(window.title) on pace to run out ~\(Formatting.countdown(to: now.addingTimeInterval(early), from: now)) early",
                    firedAt: now
                ))
            }

            ledger.fired[key] = fired
        }

        // Keep other providers' cycles; drop this provider's cycles that have rolled over.
        let others = ledger.fired.keys.filter { !$0.hasPrefix(snapshot.provider.rawValue + "|") }
        ledger.prune(keeping: live.union(others))
        return alerts
    }
}
