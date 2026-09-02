import Foundation

/// One rolling quota limit reported by a provider.
public struct QuotaWindow: Sendable, Equatable, Identifiable, Codable {
    /// Stable key within a provider, e.g. `session`, `weekly`, `weekly:Fable`.
    public var id: String
    public var title: String
    public var usedPercent: Double
    public var resetsAt: Date?
    /// Length of the window when known; used for pace projection.
    public var duration: TimeInterval?
    /// False when the provider reports the window has not begun (no reset time yet).
    public var isStarted: Bool

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?, duration: TimeInterval?, isStarted: Bool = true) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.duration = duration
        self.isStarted = isStarted
    }

    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    public static let sessionDuration: TimeInterval = 5 * 3600
    public static let weeklyDuration: TimeInterval = 7 * 24 * 3600
}

/// Pay-as-you-go / overage state. Never drives the ring; it is a dollar cap, not a percentage.
public struct ExtraUsage: Sendable, Equatable, Codable {
    public var isEnabled: Bool
    public var usedDollars: Double?
    public var limitDollars: Double?
    /// Free-form status when the provider reports a cap rather than spend, e.g. `2500 cap`.
    public var label: String?

    public init(isEnabled: Bool, usedDollars: Double? = nil, limitDollars: Double? = nil, label: String? = nil) {
        self.isEnabled = isEnabled
        self.usedDollars = usedDollars
        self.limitDollars = limitDollars
        self.label = label
    }
}

/// The complete result of one provider refresh.
public struct Snapshot: Sendable, Equatable, Codable {
    public var provider: ProviderID
    public var fetchedAt: Date
    /// `connected`, `expired`, or `absent` as reported by the provider. Staleness is derived later.
    public var status: ConnectionStatus
    public var planName: String?
    public var windows: [QuotaWindow]
    public var extraUsage: ExtraUsage?
    /// Codex on-demand rate-limit reset credits available.
    public var resetCredits: Int?

    public init(
        provider: ProviderID,
        fetchedAt: Date,
        status: ConnectionStatus,
        planName: String? = nil,
        windows: [QuotaWindow] = [],
        extraUsage: ExtraUsage? = nil,
        resetCredits: Int? = nil
    ) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.status = status
        self.planName = planName
        self.windows = windows
        self.extraUsage = extraUsage
        self.resetCredits = resetCredits
    }

    /// The most-constrained percentage window drives the ring. Nil when there are no windows.
    public var ringUsedPercent: Double? {
        windows.map(\.usedPercent).max()
    }

    public var ringRemainingPercent: Double? {
        ringUsedPercent.map { max(0, min(100, 100 - $0)) }
    }

    public static func absent(_ provider: ProviderID, at date: Date) -> Snapshot {
        Snapshot(provider: provider, fetchedAt: date, status: .absent)
    }

    public static func expired(_ provider: ProviderID, at date: Date, planName: String? = nil) -> Snapshot {
        Snapshot(provider: provider, fetchedAt: date, status: .expired, planName: planName)
    }
}
