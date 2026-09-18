import Foundation
import HeadroomCore
import Observation

/// Owns one poller per provider and mirrors their states for the UI. Also ticks a clock so
/// countdowns and staleness re-evaluate without new data.
@MainActor
@Observable
final class UsageModel {
    private(set) var states: [ProviderID: ProviderState] = [:]
    private(set) var resetSignals: [ProviderID: Date] = [:]
    var onAlert: ((UsageAlert) -> Void)?
    private var visibleSurfaces: Set<String> = []
    private var clockTask: Task<Void, Never>?
    private var started = false
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
    private var tasks: [Task<Void, Never>] = []

    init(environment: HostEnvironment = .live(), preferences: Preferences = Preferences()) {
        self.environment = environment
        self.now = environment.now()
        self.preferences = preferences
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
            OpenCodeProvider(environment: environment),
        ]
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
                        if previous?.isRestored == false, previous?.lastError == nil,
                           QuotaRecovery.confirmed(snapshot, after: previous?.snapshot, now: self.now) {
                            self.resetSignals[state.provider] = snapshot.fetchedAt
                        }
                        self.evaluateAlerts(snapshot, previous: previous?.snapshot)
                    }
                }
            })
        }
        restartClock()
    }

    var clockInterval: Duration { visibleSurfaces.isEmpty ? .seconds(60) : .seconds(1) }

    func setSurfaceVisible(_ name: String, _ visible: Bool) {
        guard visibleSurfaces.contains(name) != visible else { return }
        let wasIdle = visibleSurfaces.isEmpty
        if visible { visibleSurfaces.insert(name) } else { visibleSurfaces.remove(name) }
        now = environment.now()
        if wasIdle != visibleSurfaces.isEmpty {
            restartClock()
        }
    }

    private func restartClock() {
        clockTask?.cancel()
        let interval = clockInterval
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self else { return }
                self.now = self.environment.now()
            }
        }
    }

    isolated deinit {
        clockTask?.cancel()
    }

    func start() {
        guard !started else { return }
        started = true
        for poller in pollers.values {
            Task { await poller.start() }
        }
    }

    func refreshAll() {
        for poller in pollers.values {
            Task { await poller.refreshNow() }
        }
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
        for alert in alerts where allowsAlert(alert) { onAlert?(alert) }
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

    /// Providers to draw, in the user's order: signed in, and not hidden. A provider you are
    /// not signed into has nothing to say, so there is no "always show".
    var visibleProviders: [ProviderID] {
        preferences.order.filter { preferences.tier($0) != .hidden && isDetected($0) }
    }

    /// Main agents — the ones whose quota actually stops your work. These alone decide whether
    /// the island appears at all.
    var mainProviders: [ProviderID] {
        visibleProviders.filter { preferences.tier($0) == .main }
    }

    /// Side providers: research, one-offs, anything you would not notice running out.
    var secondaryProviders: [ProviderID] {
        visibleProviders.filter { preferences.tier($0) == .secondary }
    }

    /// Whether this provider has something a person needs to know: quota past the first urgency
    /// step, or a login that stopped working. Everything else is silence.
    func isSpeaking(_ id: ProviderID) -> Bool {
        guard let state = states[id] else { return false }
        if status(id) == .expired || state.isErrored { return true }
        guard let used = state.snapshot?.ringUsedPercent else { return false }
        return Urgency(usedPercent: used) != .fine
    }

    /// Gauges the band shows, left of the notch: the main agents that are speaking.
    var compactMain: [ProviderID] { mainProviders.filter(isSpeaking) }

    /// Gauges the band shows, right of the notch: side providers that are speaking. They ride
    /// along once the island is up, but never summon it on their own.
    var compactSecondary: [ProviderID] {
        compactMain.isEmpty ? [] : secondaryProviders.filter(isSpeaking)
    }

    /// Nothing to say: no main agent is near its limit and none is broken. The island draws
    /// nothing at all until that changes.
    var isDormant: Bool { compactMain.isEmpty }

    enum GaugeSide { case left, right, none }

    func gaugeSide(_ id: ProviderID) -> GaugeSide {
        if compactMain.contains(id) { return .left }
        if compactSecondary.contains(id) { return .right }
        return .none
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
