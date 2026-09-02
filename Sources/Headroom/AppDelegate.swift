import AppKit
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?
    private var model: UsageModel?
    private var settings: SettingsWindowController?
    private var statusItem: StatusItemController?
    private var fullScreen: FullScreenObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = UsageModel()
        let island = IslandController(model: model)
        let settings = SettingsWindowController(model: model)
        let statusItem = StatusItemController()
        let fullScreen = FullScreenObserver()

        island.onOpenSettings = { settings.show() }
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
