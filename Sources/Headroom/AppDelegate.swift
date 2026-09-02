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
        fullScreen.onChange = { [weak self] active in
            guard let self, let model = self.model else { return }
            self.island?.setHidden(active && model.preferences.hideInFullScreen)
        }

        island.show()
        model.start()
        model.preferences.registerLoginItemOnFirstRun()

        self.model = model
        self.island = island
        self.settings = settings
        self.statusItem = statusItem
        self.fullScreen = fullScreen
        observePreferences()
    }

    /// Re-apply preference-driven side effects whenever they change.
    private func observePreferences() {
        guard let model, let statusItem, let island, let fullScreen else { return }
        withObservationTracking {
            statusItem.isShown = model.preferences.showMenuBarIcon
            island.setHidden(fullScreen.isFullScreen && model.preferences.hideInFullScreen)
        } onChange: {
            Task { @MainActor [weak self] in self?.observePreferences() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
