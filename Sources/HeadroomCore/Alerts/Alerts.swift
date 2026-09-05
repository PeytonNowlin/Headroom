import Foundation

public struct UsageAlert: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable, Hashable {
        case threshold(Int)
        case paceExhaustion
        case quotaReturned

        var ledgerKey: String {
            switch self {
            case let .threshold(p): "t\(p)"
            case .paceExhaustion: "pace"
            case .quotaReturned: "returned"
            }
        }
    }

    public var provider: ProviderID
    public var windowID: String
    public var kind: Kind
    public var message: String
    public var firedAt: Date
    public var resetsAt: Date? = nil

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

/// Warning settings and cycle-specific snoozes survive relaunches. Optional preference fields
/// in the app allow older installations to retain all their existing settings.
public struct AlertOptions: Codable, Equatable, Sendable {
    public var warningsEnabled = true
    public var notifyOnReset = false
    public var snoozedCycles: Set<String> = []

    public init() {}

    public mutating func snooze(_ snapshot: Snapshot) {
        snoozedCycles = Set(snapshot.windows.filter { $0.resetsAt != nil }.map {
            AlertLedger.cycleKey(snapshot.provider, $0)
        })
    }

    public func isSnoozed(provider: ProviderID, window: QuotaWindow) -> Bool {
        snoozedCycles.contains(AlertLedger.cycleKey(provider, window))
    }
}

public enum AlertEvaluator {
    public static let thresholds = [80, 95]

    /// One message per window, combining newly crossed thresholds with a reliable pace warning.
    /// Recovery is confirmed from fresh provider data rather than inferred from a countdown.
    public static func evaluate(_ snapshot: Snapshot, now: Date, ledger: inout AlertLedger,
                                previous: Snapshot? = nil, options: AlertOptions = AlertOptions(),
                                forecasts: [String: Pace.Forecast] = [:]) -> [UsageAlert] {
        guard snapshot.status == .connected,
              now.timeIntervalSince(snapshot.fetchedAt) <= 10 * 60,
              snapshot.fetchedAt <= now else { return [] }
        var alerts: [UsageAlert] = []
        var live: Set<String> = []

        for window in snapshot.windows {
            let key = AlertLedger.cycleKey(snapshot.provider, window)
            live.insert(key)
            var fired = ledger.fired[key] ?? []
            defer { ledger.fired[key] = fired }
            guard window.usedPercent.isFinite else { continue }

            if options.notifyOnReset, !fired.contains("returned"),
               let previous, previous.provider == snapshot.provider,
               previous.fetchedAt < snapshot.fetchedAt,
               let old = previous.windows.first(where: { $0.id == window.id }),
               let oldReset = old.resetsAt,
               old.usedPercent >= 80, window.usedPercent < 80,
               // Claude leaves the next session unstarted until the user uses it again.
               // Its fresh zero-usage response confirms recovery only after the old reset.
               (window.isStarted && window.resetsAt.map { $0 > oldReset && $0 > now } == true)
                || (!window.isStarted && window.resetsAt == nil && window.usedPercent == 0
                    && oldReset <= snapshot.fetchedAt) {
                fired.insert("returned")
                alerts.append(UsageAlert(provider: snapshot.provider, windowID: window.id,
                                         kind: .quotaReturned,
                                         message: "\(snapshot.provider.displayName) \(window.title) quota available again · \(Int(window.remainingPercent.rounded()))% left",
                                         firedAt: now, resetsAt: window.resetsAt))
                continue
            }

            guard window.isStarted, window.resetsAt.map({ $0 > now }) ?? true,
                  options.warningsEnabled, !options.isSnoozed(provider: snapshot.provider, window: window) else { continue }
            let crossed = thresholds.filter { window.usedPercent >= Double($0) && !fired.contains("t\($0)") }
            crossed.forEach { fired.insert("t\($0)") }
            var paceText: String?
            if case let .runsOut(early)? = forecasts[window.id]?.warning, early > 0,
               !fired.contains("pace"), window.usedPercent < 100 {
                fired.insert("pace")
                paceText = "recent pace may run out ~\(Formatting.countdown(to: now.addingTimeInterval(early), from: now)) early"
            }
            guard !crossed.isEmpty || paceText != nil else { continue }
            let kind: UsageAlert.Kind = crossed.last.map { .threshold($0) } ?? .paceExhaustion
            var message = "\(snapshot.provider.displayName) \(window.title) at \(Int(window.usedPercent.rounded()))% used"
            if let paceText { message += " · \(paceText)" }
            if let reset = window.resetsAt {
                message += " · resets in \(Formatting.countdown(to: reset, from: now))"
            }
            alerts.append(UsageAlert(provider: snapshot.provider, windowID: window.id,
                                     kind: kind, message: message, firedAt: now, resetsAt: window.resetsAt))
        }

        let others = ledger.fired.keys.filter { !$0.hasPrefix(snapshot.provider.rawValue + "|") }
        ledger.prune(keeping: live.union(others))
        return alerts
    }
}
