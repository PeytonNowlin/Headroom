import Foundation
import HeadroomCore
import Observation

/// Owns one poller per provider and mirrors their states for the UI. Also ticks a clock so
/// countdowns and staleness re-evaluate without new data.
@MainActor
@Observable
final class UsageModel {
    private(set) var states: [ProviderID: ProviderState] = [:]
    private(set) var spend: [ProviderID: SpendSummary] = [:]
    private(set) var now = Date()

    let environment: HostEnvironment
    private var pollers: [ProviderID: ProviderPoller] = [:]
    private var scanners: [ProviderID: SpendScanner] = [:]
    private let pricing: PricingStore
    private var tasks: [Task<Void, Never>] = []
    static let spendInterval: Duration = .seconds(120)

    init(environment: HostEnvironment = .live()) {
        self.environment = environment
        pricing = PricingStore(environment: environment)
        let runtimes: [any ProviderRuntime] = [
            ClaudeProvider(environment: environment),
            CodexProvider(environment: environment),
            GrokProvider(environment: environment),
        ]
        let formats: [any UsageLogFormat] = [ClaudeLogFormat(), CodexLogFormat(), GrokLogFormat()]
        for format in formats {
            scanners[format.provider] = SpendScanner(format: format, environment: environment)
        }
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
        tasks.append(Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await self?.rescanSpend()
                try? await Task.sleep(for: Self.spendInterval)
            }
        })
    }

    func refreshAll() {
        for poller in pollers.values {
            Task { await poller.refreshNow() }
        }
        Task { await rescanSpend() }
    }

    private func rescanSpend() async {
        let table = await pricing.refreshIfNeeded()
        let calendar = environment.calendar
        for (id, scanner) in scanners {
            guard scanner.hasLogs() else { continue }
            let ledger = await scanner.scan()
            spend[id] = SpendSummarizer.summarize(ledger, pricing: table, now: environment.now(), calendar: calendar)
        }
    }

    /// Sum across every provider with logs. Nil until all of them have reported at least once, so
    /// a first-launch scan still in progress never shows a partial number as the total.
    var totalSpend: SpendSummary? {
        let expected = scanners.filter { $0.value.hasLogs() }.map(\.key)
        guard !expected.isEmpty, expected.allSatisfy({ spend[$0] != nil }) else { return nil }
        let all = expected.compactMap { spend[$0] }
        guard let first = all.first else { return nil }
        return all.dropFirst().reduce(first, +)
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
