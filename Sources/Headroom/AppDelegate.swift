import AppKit
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?
    private var model: UsageModel?
    private var settings: SettingsWindowController?
    private var statusItem: StatusItemController?
    private var fullScreen: FullScreenObserver?
    private var updater: UpdateController?
    private var notifications: NotificationController?
    private var trends: TrendsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = UsageModel()
        let island = IslandController(model: model)
        let updater = UpdateController()
        let notifications = NotificationController(preferences: model.preferences)
        let trends = TrendsWindowController(model: model)
        let settings = SettingsWindowController(model: model, updater: updater, notifications: notifications)
        let statusItem = StatusItemController()
        let fullScreen = FullScreenObserver()

        island.onOpenSettings = { settings.show() }
        island.onOpenTrends = { trends.show(provider: $0) }
        island.onCheckForUpdates = { updater.checkForUpdates() }
        settings.onOpenTrends = { trends.show() }
        statusItem.onTrends = { trends.show() }
        statusItem.onUpdates = { updater.checkForUpdates() }
        model.onAlert = { [weak notifications] alert in notifications?.deliver(alert) }
        notifications.onOpenProvider = { [weak island] in island?.openProvider($0) }
        notifications.onSnooze = { [weak model] provider, windowID, reset in
            guard let model,
                  let window = model.state(provider)?.snapshot?.windows.first(where: { $0.id == windowID }),
                  NotificationController.resetKey(window.resetsAt) == reset else { return }
            model.snoozeAlerts(provider)
        }
        statusItem.onRefresh = { model.refreshAll() }
        statusItem.onTogglePin = { island.togglePinned() }
        statusItem.onSettings = { settings.show() }
        fullScreen.onChange = { [weak self] displays in
            guard let self, let model = self.model else { return }
            self.island?.setHidden(on: model.preferences.hideInFullScreen ? displays : [])
        }

        island.show()
        model.start()
        model.preferences.registerLoginItemOnFirstRun()
        scheduleFirstRunGuidance(model: model, island: island)

        self.model = model
        self.island = island
        self.settings = settings
        self.statusItem = statusItem
        self.fullScreen = fullScreen
        self.updater = updater
        self.notifications = notifications
        self.trends = trends
        observePreferences()
    }

    /// Once the first poll has settled, if nothing was detected, show guidance exactly once.
    private func scheduleFirstRunGuidance(model: UsageModel, island: IslandController) {
        guard !model.preferences.didCompleteFirstRun else { return }
        Task { @MainActor in
            for _ in 0..<40 where model.isAnyRefreshing || model.states.isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
            }
            model.preferences.didCompleteFirstRun = true
            if model.visibleProviders.isEmpty {
                island.showFirstRunGuidance()
            }
        }
    }

    /// Re-apply preference-driven side effects whenever they change.
    private func observePreferences() {
        guard let model, let statusItem, let island, let fullScreen else { return }
        withObservationTracking {
            statusItem.isShown = model.preferences.showMenuBarIcon
            island.setHidden(on: model.preferences.hideInFullScreen ? fullScreen.fullScreenDisplays : [])
        } onChange: {
            Task { @MainActor [weak self] in self?.observePreferences() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
