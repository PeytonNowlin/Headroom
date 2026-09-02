import Foundation
import HeadroomCore
import Observation

/// Owns one poller per provider and mirrors their states for the UI. Also ticks a clock so
/// countdowns and staleness re-evaluate without new data.
@MainActor
@Observable
final class UsageModel {
    private(set) var states: [ProviderID: ProviderState] = [:]
    private(set) var now = Date()

    let environment: HostEnvironment
    private var pollers: [ProviderID: ProviderPoller] = [:]
    private var tasks: [Task<Void, Never>] = []

    init(environment: HostEnvironment = .live()) {
        self.environment = environment
        let runtimes: [any ProviderRuntime] = [
            ClaudeProvider(environment: environment),
            CodexProvider(environment: environment),
        ]
        for runtime in runtimes {
            let poller = ProviderPoller(runtime: runtime, environment: environment)
            pollers[runtime.id] = poller
            states[runtime.id] = ProviderState(provider: runtime.id)
            tasks.append(Task { [weak self] in
                for await state in poller.states {
                    guard let self else { return }
                    self.states[state.provider] = state
                }
            })
        }
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.now = Date()
            }
        })
    }

    func start() {
        for poller in pollers.values {
            Task { await poller.start() }
        }
    }

    func refreshAll() {
        for poller in pollers.values {
            Task { await poller.refreshNow() }
        }
    }

    /// Providers worth drawing: anything with credentials, plus anything mid-first-refresh.
    var visibleProviders: [ProviderID] {
        ProviderID.allCases.filter { id in
            guard let state = states[id] else { return false }
            if let snapshot = state.snapshot { return snapshot.status != .absent }
            return state.isRefreshing
        }
    }

    func state(_ id: ProviderID) -> ProviderState? { states[id] }

    func status(_ id: ProviderID) -> ConnectionStatus {
        states[id]?.status(at: now) ?? .absent
    }
}
