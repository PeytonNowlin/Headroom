import AppKit
import SwiftUI

/// A compact, System-Settings-density window. Activating the app for it is deliberate: the
/// hotkey recorder and drag-reorder need real keyboard and drag focus.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: UsageModel

    init(model: UsageModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let view = SettingsView(model: model, preferences: model.preferences)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Headroom Settings"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 440, height: 620))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
