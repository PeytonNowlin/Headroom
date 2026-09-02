import Foundation

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

    public init(provider: ProviderID, snapshot: Snapshot? = nil, lastError: String? = nil,
                consecutiveFailures: Int = 0, isRefreshing: Bool = false) {
        self.provider = provider
        self.snapshot = snapshot
        self.lastError = lastError
        self.consecutiveFailures = consecutiveFailures
        self.isRefreshing = isRefreshing
    }

    public static let stalenessWindow: TimeInterval = 5 * 60

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

    public init(runtime: any ProviderRuntime, environment: HostEnvironment,
                interval: Duration = .seconds(60), backoff: BackoffPolicy = .standard) {
        self.runtime = runtime
        self.environment = environment
        self.interval = interval
        self.backoff = backoff
        self.state = ProviderState(provider: runtime.id)
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

    /// Interrupts the current wait so the next refresh happens immediately.
    public func refreshNow() {
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
        publish { $0.isRefreshing = true }
        do {
            let snapshot = try await runtime.refresh()
            publish {
                $0.snapshot = snapshot
                $0.lastError = nil
                $0.consecutiveFailures = 0
                $0.isRefreshing = false
            }
            return interval
        } catch {
            publish {
                $0.consecutiveFailures += 1
                $0.lastError = Self.describe(error)
                $0.isRefreshing = false
            }
            return backoff.delay(afterFailures: state.consecutiveFailures)
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
            case let .malformedResponse(msg): return "Malformed response: \(msg)"
            }
        }
        return String(describing: error)
    }
}
