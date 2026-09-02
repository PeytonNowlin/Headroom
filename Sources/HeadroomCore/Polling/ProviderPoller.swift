import Foundation

public extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Exponential back-off for retryable refresh failures.
public struct BackoffPolicy: Sendable, Equatable {
    public var base: Duration
    public var maximum: Duration

    public init(base: Duration, maximum: Duration) {
        self.base = base
        self.maximum = maximum
    }

    public static let standard = BackoffPolicy(base: .seconds(60), maximum: .seconds(15 * 60))

    /// Delay before the next attempt after `failures` consecutive failures (1-based).
    public func delay(afterFailures failures: Int) -> Duration {
        guard failures > 0 else { return base }
        let exponent = min(failures - 1, 10)
        let scaled = base * (1 << exponent)
        return min(scaled, maximum)
    }
}

/// What the UI observes for one provider: the last good snapshot plus derived freshness.
public struct ProviderState: Sendable, Equatable {
    public var provider: ProviderID
    public var snapshot: Snapshot?
    public var lastError: String?
    public var consecutiveFailures: Int
    public var isRefreshing: Bool
    /// Whether any credential source exists locally, independent of whether a refresh has
    /// succeeded. A provider with credentials stays visible even while every refresh fails.
    public var hasCredentials: Bool
    /// After a 429, no request (scheduled or manual) goes out before this instant.
    public var rateLimitedUntil: Date?

    public init(provider: ProviderID, snapshot: Snapshot? = nil, lastError: String? = nil,
                consecutiveFailures: Int = 0, isRefreshing: Bool = false, hasCredentials: Bool = false,
                rateLimitedUntil: Date? = nil) {
        self.provider = provider
        self.snapshot = snapshot
        self.lastError = lastError
        self.consecutiveFailures = consecutiveFailures
        self.isRefreshing = isRefreshing
        self.hasCredentials = hasCredentials
        self.rateLimitedUntil = rateLimitedUntil
    }

    public func isRateLimited(at now: Date) -> Bool {
        rateLimitedUntil.map { $0 > now } ?? false
    }

    /// True when we have credentials but no snapshot and the last attempt failed.
    public var isErrored: Bool { snapshot == nil && lastError != nil }

    /// Three missed polls before a snapshot reads as stale.
    public static let stalenessWindow: TimeInterval = 3 * ProviderPoller.defaultInterval

    /// Connection status at `now`, folding staleness in.
    public func status(at now: Date) -> ConnectionStatus {
        guard let snapshot else { return .absent }
        switch snapshot.status {
        case .absent, .expired:
            return snapshot.status
        case .connected, .stale:
            return now.timeIntervalSince(snapshot.fetchedAt) > Self.stalenessWindow ? .stale : .connected
        }
    }
}

/// Runs one provider's refresh loop: poll on an interval, back off on transient failure,
/// keep the last snapshot while retrying, publish every state change.
public actor ProviderPoller {
    private let runtime: any ProviderRuntime
    private let environment: HostEnvironment
    private let interval: Duration
    private let backoff: BackoffPolicy
    private var state: ProviderState
    private var continuation: AsyncStream<ProviderState>.Continuation?
    private var loop: Task<Void, Never>?
    private var wake: CheckedContinuation<Void, Never>?

    public nonisolated let states: AsyncStream<ProviderState>

    /// Poll cadence, matching OpenUsage: one fetch per provider every five minutes, plus launch
    /// and the manual Refresh. Anything faster invites 429s from the usage endpoints.
    public static let defaultInterval: TimeInterval = 5 * 60

    public init(runtime: any ProviderRuntime, environment: HostEnvironment,
                interval: Duration = .seconds(defaultInterval), backoff: BackoffPolicy = .standard,
                initialSnapshot: Snapshot? = nil, rateLimitedUntil: Date? = nil) {
        self.runtime = runtime
        self.environment = environment
        self.interval = interval
        self.backoff = backoff
        self.state = ProviderState(provider: runtime.id, snapshot: initialSnapshot,
                                   hasCredentials: runtime.hasLocalCredentials(),
                                   rateLimitedUntil: rateLimitedUntil)
        var cont: AsyncStream<ProviderState>.Continuation?
        self.states = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { cont = $0 }
        self.continuation = cont
    }

    public var current: ProviderState { state }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.refreshAndScheduleDelay()
                await self.waitFor(delay)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        wake?.resume()
        wake = nil
    }

    /// Interrupts the current wait so the next refresh happens immediately — unless the provider
    /// is cooling down from a 429, in which case the request is deliberately not made.
    public func refreshNow() {
        if state.isRateLimited(at: environment.now()) {
            HeadroomLog.polling.info("\(self.runtime.id.rawValue, privacy: .public) manual refresh skipped: rate-limit cooldown")
            return
        }
        if let wake {
            self.wake = nil
            wake.resume()
        }
    }

    /// Performs one refresh and returns how long to wait before the next.
    @discardableResult
    public func refreshOnce() async -> ProviderState {
        _ = await refreshAndScheduleDelay()
        return state
    }

    private func refreshAndScheduleDelay() async -> Duration {
        let now = environment.now()
        if let until = state.rateLimitedUntil, until > now {
            // Still cooling down (e.g. restored from disk after a relaunch): wait it out first.
            return .seconds(until.timeIntervalSince(now))
        }
        let credentialed = runtime.hasLocalCredentials()
        publish {
            $0.isRefreshing = true
            $0.hasCredentials = credentialed
            $0.rateLimitedUntil = nil
        }
        do {
            let snapshot = try await runtime.refresh()
            HeadroomLog.polling.info("\(self.runtime.id.rawValue, privacy: .public) refreshed: \(String(describing: snapshot.status), privacy: .public), \(snapshot.windows.count) windows")
            publish {
                $0.snapshot = snapshot
                $0.lastError = nil
                $0.consecutiveFailures = 0
                $0.isRefreshing = false
            }
            return interval
        } catch {
            HeadroomLog.polling.error("\(self.runtime.id.rawValue, privacy: .public) failed: \(Self.describe(error), privacy: .public)")
            publish {
                $0.consecutiveFailures += 1
                $0.lastError = Self.describe(error)
                $0.isRefreshing = false
            }
            let delay = backoff.delay(afterFailures: state.consecutiveFailures)
            if case let .rateLimited(hint) = error as? ProviderError {
                // Never sooner than the next regular slot; later if the server asked for it.
                let cooldown = max(interval, hint.map { Duration.seconds($0) } ?? .zero, delay)
                let until = environment.now().addingTimeInterval(cooldown.seconds)
                publish { $0.rateLimitedUntil = until }
                return cooldown
            }
            return delay
        }
    }

    private func waitFor(_ delay: Duration) async {
        let sleeper = Task { [environment] in
            try await environment.sleep(delay)
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            wake = c
            Task { [weak self] in
                _ = await sleeper.result
                await self?.resumeWake()
            }
        }
        sleeper.cancel()
    }

    private func resumeWake() {
        if let wake {
            self.wake = nil
            wake.resume()
        }
    }

    private func publish(_ mutate: (inout ProviderState) -> Void) {
        mutate(&state)
        continuation?.yield(state)
    }

    private static func describe(_ error: Error) -> String {
        if let p = error as? ProviderError {
            switch p {
            case let .transient(code?): return "HTTP \(code)"
            case .transient(nil): return "Network unavailable"
            case .rateLimited: return "Rate limited"
            case let .malformedResponse(msg): return "Malformed response: \(msg)"
            }
        }
        return String(describing: error)
    }
}
