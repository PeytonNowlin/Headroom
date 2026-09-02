import AppKit

/// Optional menu bar icon mirroring the island's context menu, for users who want a
/// discoverable handle or run without a notch.
@MainActor
final class StatusItemController {
    private var item: NSStatusItem?
    var onRefresh: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onSettings: () -> Void = {}

    var isShown: Bool {
        get { item != nil }
        set { newValue ? show() : hide() }
    }

    private func show() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: "Headroom")
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(action(title: "Refresh Now", #selector(refresh), "r"))
        menu.addItem(action(title: "Toggle Island", #selector(togglePin), ""))
        menu.addItem(.separator())
        menu.addItem(action(title: "Settings…", #selector(settings), ","))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Headroom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        self.item = item
    }

    private func hide() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func action(title: String, _ selector: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func refresh() { onRefresh() }
    @objc private func togglePin() { onTogglePin() }
    @objc private func settings() { onSettings() }
}
