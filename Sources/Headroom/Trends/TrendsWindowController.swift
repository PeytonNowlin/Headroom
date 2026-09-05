import AppKit
import HeadroomCore
import SwiftUI

@MainActor
final class TrendsWindowController: NSObject, NSWindowDelegate {
    private let model: UsageModel
    private var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?

    init(model: UsageModel) { self.model = model }

    func show(provider: ProviderID? = nil) {
        if let hosting {
            hosting.rootView = AnyView(TrendsView(model: model, provider: provider).id(UUID()))
        } else {
            let hosting = NSHostingController(rootView: AnyView(TrendsView(model: model, provider: provider).id(UUID())))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Headroom — Usage Trends"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 680, height: 680))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.hosting = hosting
            self.window = window
        }
        model.setSurfaceVisible("trends", true)
        NSApp.activate()
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { model.setSurfaceVisible("trends", false) }
    func windowDidMiniaturize(_ notification: Notification) { model.setSurfaceVisible("trends", false) }
    func windowDidDeminiaturize(_ notification: Notification) { model.setSurfaceVisible("trends", true) }
}
