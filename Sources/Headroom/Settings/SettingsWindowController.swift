import AppKit
import SwiftUI

/// A compact, System-Settings-density window. Activating the app for it is deliberate: the
/// hotkey recorder and drag-reorder need real keyboard and drag focus.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: UsageModel
    private let updater: UpdateController?
    private let notifications: NotificationController?
    var onOpenTrends: () -> Void = {}

    init(model: UsageModel, updater: UpdateController? = nil, notifications: NotificationController? = nil) {
        self.model = model
        self.updater = updater
        self.notifications = notifications
    }

    func show() {
        if window == nil {
            let view = SettingsView(model: model, preferences: model.preferences, updater: updater,
                                    notifications: notifications, onOpenTrends: { [weak self] in self?.onOpenTrends() })
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Headroom Settings"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 520, height: 720))
            window.center()
            self.window = window
        }
        model.setSurfaceVisible("settings", true)
        Task { await notifications?.refreshAuthorization() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { model.setSurfaceVisible("settings", false) }
}
