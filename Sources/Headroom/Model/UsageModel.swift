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
    /// Providers the last rescan expected spend from: local logs, or a Cursor login. Captured
    /// there, never derived in a view: the checks behind it shell out (sqlite3, security) and
    /// must stay off the main thread and out of SwiftUI body evaluation.
    private(set) var spendProviders: [ProviderID] = []
    private(set) var now = Date()
    /// The banner currently showing, if any; further alerts queue behind it.
    private(set) var activeAlert: UsageAlert?
    private var alertQueue: [UsageAlert] = []
    private(set) var usageHistory: UsageHistory
    private var alertLedger: AlertLedger
    private var bannerTask: Task<Void, Never>?

    let environment: HostEnvironment
    let preferences: Preferences
    private var pollers: [ProviderID: ProviderPoller] = [:]
    private var scanners: [ProviderID: SpendScanner] = [:]
    private let cursorSpend: CursorSpendSource
    private let pricing: PricingStore
    private var tasks: [Task<Void, Never>] = []
    static let spendInterval: Duration = .seconds(120)

    init(environment: HostEnvironment = .live(), preferences: Preferences = Preferences()) {
        self.environment = environment
        self.now = environment.now()
        self.preferences = preferences
        pricing = PricingStore(environment: environment)
        cursorSpend = CursorSpendSource(environment: environment)
        alertLedger = Self.loadLedger(environment)
        if let data = try? environment.readFile(environment.dataDirectory.appending(path: "quota-history.json")),
           let history = try? JSONDecoder().decode(UsageHistory.self, from: data) {
            usageHistory = history
        } else {
            usageHistory = UsageHistory()
        }
        let runtimes: [any ProviderRuntime] = [
            ClaudeProvider(environment: environment),
            CodexProvider(environment: environment),
            GrokProvider(environment: environment),
            CursorProvider(environment: environment),
        ]
        let formats: [any UsageLogFormat] = [ClaudeLogFormat(), CodexLogFormat(), GrokLogFormat()]
        for format in formats {
            scanners[format.provider] = SpendScanner(format: format, environment: environment)
        }
        let store = SnapshotStore(environment: environment)
        let restored = store.load()
        for runtime in runtimes {
            let entry = restored[runtime.id]
            let poller = ProviderPoller(runtime: runtime, environment: environment,
                                        initialSnapshot: entry?.snapshot,
                                        rateLimitedUntil: entry?.rateLimitedUntil)
            pollers[runtime.id] = poller
            // Mirrors the poller's seed; the first poll corrects it off the main thread.
            states[runtime.id] = ProviderState(provider: runtime.id, snapshot: entry?.snapshot,
                                               hasCredentials: entry?.snapshot.map { $0.status != .absent } ?? false,
                                               rateLimitedUntil: entry?.rateLimitedUntil, isRestored: entry?.snapshot != nil)
            tasks.append(Task { [weak self] in
                for await state in poller.states {
                    guard let self else { return }
                    self.now = self.environment.now()
                    let previous = self.states[state.provider]
                    self.states[state.provider] = state
                    if state.snapshot != previous?.snapshot || state.rateLimitedUntil != previous?.rateLimitedUntil {
                        self.persistSnapshots()
                    }
                    if let snapshot = state.snapshot, snapshot != previous?.snapshot {
                        self.usageHistory.record(snapshot)
                        if let data = try? JSONEncoder().encode(self.usageHistory) {
                            try? self.environment.writeFile(self.environment.dataDirectory.appending(path: "quota-history.json"), data)
                        }
                        self.evaluateAlerts(snapshot, previous: previous?.snapshot)
                    }
                }
            })
        }
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if let self { self.now = self.environment.now() }
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

    func refresh(_ provider: ProviderID) {
        Task { await pollers[provider]?.refreshNow() }
    }

    func forecast(_ window: QuotaWindow, provider: ProviderID) -> Pace.Forecast? {
        guard let state = states[provider], state.lastError == nil,
              state.status(at: now) == .connected else { return nil }
        return Pace.forecast(window, provider: provider, history: usageHistory, now: now)
    }

    func setAlertOptions(_ options: AlertOptions, for provider: ProviderID) {
        preferences.setAlertOptions(options, for: provider)
        alertQueue.removeAll { $0.provider == provider && !allowsAlert($0) }
        if let activeAlert, activeAlert.provider == provider, !allowsAlert(activeAlert) { dismissAlert() }
    }

    func snoozeAlerts(_ provider: ProviderID) {
        guard let snapshot = states[provider]?.snapshot else { return }
        var options = preferences.alertOptions(provider)
        options.snooze(snapshot)
        setAlertOptions(options, for: provider)
    }

    func resumeAlerts(_ provider: ProviderID) {
        var options = preferences.alertOptions(provider)
        options.snoozedCycles = []
        setAlertOptions(options, for: provider)
    }

    func alertsSnoozed(_ provider: ProviderID) -> Bool {
        let options = preferences.alertOptions(provider)
        return states[provider]?.snapshot?.windows.contains {
            ($0.resetsAt.map { $0 > now } ?? false) && options.isSnoozed(provider: provider, window: $0)
        } ?? false
    }

    private func allowsAlert(_ alert: UsageAlert) -> Bool {
        let options = preferences.alertOptions(alert.provider)
        guard now.timeIntervalSince(alert.firedAt) < 10 * 60,
              let window = states[alert.provider]?.snapshot?.windows.first(where: { $0.id == alert.windowID }),
              window.resetsAt == alert.resetsAt,
              window.resetsAt.map({ $0 > now }) ?? true else { return false }
        if alert.kind == .quotaReturned { return options.notifyOnReset }
        guard options.warningsEnabled else { return false }
        return !options.isSnoozed(provider: alert.provider, window: window)
    }

    private func rescanSpend() async {
        let table = await pricing.refreshIfNeeded()
        let calendar = environment.calendar
        var expected: [ProviderID] = []
        for (id, scanner) in scanners {
            guard scanner.hasLogs() else { continue }
            expected.append(id)
            let ledger = await scanner.scan()
            spend[id] = SpendSummarizer.summarize(ledger, pricing: table, now: environment.now(), calendar: calendar)
        }
        // `ledger()` is nil only without a login; the token read happens inside the actor.
        if let ledger = await cursorSpend.ledger() {
            expected.append(.cursor)
            spend[.cursor] = SpendSummarizer.summarize(ledger, pricing: table, now: environment.now(), calendar: calendar)
        }
        spendProviders = expected
    }

    /// Sum across every provider with spend. Nil until a rescan has completed with all of them
    /// reported, so a first-launch scan still in progress never shows a partial number as the total.
    var totalSpend: SpendSummary? {
        let expected = spendProviders
        guard !expected.isEmpty, expected.allSatisfy({ spend[$0] != nil }) else { return nil }
        let all = expected.compactMap { spend[$0] }
        guard let first = all.first else { return nil }
        return all.dropFirst().reduce(first, +)
    }

    // MARK: - Alerts

    private static let ledgerFile = "alerts.json"

    private static func loadLedger(_ environment: HostEnvironment) -> AlertLedger {
        guard let data = try? environment.readFile(environment.dataDirectory.appending(path: ledgerFile)),
              let ledger = try? JSONDecoder().decode(AlertLedger.self, from: data) else { return AlertLedger() }
        return ledger
    }

    private func evaluateAlerts(_ snapshot: Snapshot, previous: Snapshot?) {
        let forecasts = Dictionary(uniqueKeysWithValues: snapshot.windows.compactMap { window in
            forecast(window, provider: snapshot.provider).map { (window.id, $0) }
        })
        let alerts = AlertEvaluator.evaluate(snapshot, now: environment.now(), ledger: &alertLedger,
                                            previous: previous, options: preferences.alertOptions(snapshot.provider),
                                            forecasts: forecasts)
        if let data = try? JSONEncoder().encode(alertLedger) {
            try? environment.writeFile(environment.dataDirectory.appending(path: Self.ledgerFile), data)
        }
        if let activeAlert, !allowsAlert(activeAlert) { dismissAlert() }
        guard !alerts.isEmpty else { return }
        alertQueue.append(contentsOf: alerts)
        showNextAlert()
    }

    private func showNextAlert() {
        alertQueue.removeAll { !allowsAlert($0) }
        guard activeAlert == nil, !alertQueue.isEmpty else { return }
        activeAlert = alertQueue.removeFirst()
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.bannerDwell)
            guard !Task.isCancelled else { return }
            self?.dismissAlert()
        }
    }

    func dismissAlert() {
        bannerTask?.cancel()
        activeAlert = nil
        showNextAlert()
    }

    private func persistSnapshots() {
        var entries: [ProviderID: SnapshotStore.Entry] = [:]
        for (id, state) in states {
            let snapshot = state.snapshot.flatMap { $0.status == .absent ? nil : $0 }
            if snapshot != nil || state.rateLimitedUntil != nil {
                entries[id] = SnapshotStore.Entry(snapshot: snapshot, rateLimitedUntil: state.rateLimitedUntil)
            }
        }
        SnapshotStore(environment: environment).save(entries)
    }

    /// Whether a provider has anything to show on its own merits: local credentials, a
    /// non-absent snapshot, or a first refresh in flight. A failing provider stays on screen.
    func isDetected(_ id: ProviderID) -> Bool {
        guard let state = states[id] else { return false }
        if let snapshot = state.snapshot { return snapshot.status != .absent || state.hasCredentials }
        return state.hasCredentials || state.isRefreshing
    }

    /// Providers to draw, in the user's order, honoring per-provider visibility overrides.
    var visibleProviders: [ProviderID] {
        preferences.order.filter { id in
            switch preferences.visibility(id) {
            case .show: true
            case .hide: false
            case .auto: isDetected(id)
            }
        }
    }

    /// Providers that get a compact dot: only those with a quota (or an expired/failing login)
    /// to summarize. The first half sit left of the notch, the rest right.
    var dotProviders: [ProviderID] {
        visibleProviders.filter { ProviderDot.shows(state: states[$0], status: status($0)) }
    }

    enum DotSide { case left, right, none }

    func dotSide(_ id: ProviderID) -> DotSide {
        let dots = dotProviders
        guard let index = dots.firstIndex(of: id) else { return .none }
        return index < (dots.count + 1) / 2 ? .left : .right
    }

    /// The soonest scheduled refresh across visible providers.
    var nextRefreshAt: Date? {
        visibleProviders.compactMap { states[$0]?.nextRefreshAt }.min()
    }

    var isAnyRefreshing: Bool {
        visibleProviders.contains { states[$0]?.isRefreshing == true }
    }

    func state(_ id: ProviderID) -> ProviderState? { states[id] }

    func status(_ id: ProviderID) -> ConnectionStatus {
        states[id]?.status(at: now) ?? .absent
    }
}
