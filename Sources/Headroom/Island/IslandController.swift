import AppKit
import HeadroomCore
import KeyboardShortcuts
import SwiftUI

/// Owns the island panel, its state machine, and screen anchoring.
@MainActor
final class IslandController {
    private let state: IslandState
    private let model: UsageModel
    private var panel: IslandPanel?
    private var host: IslandHostView?
    private var dwellTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?
    private var hovering = false

    var onOpenSettings: () -> Void = {}

    init(model: UsageModel) {
        self.model = model
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let anchor = IslandGeometry.anchor(for: screen)
        state = IslandState(layout: IslandLayout.make(for: anchor))
    }

    func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = IslandGeometry.panelFrame(layout: state.layout, on: screen)
        let panel = IslandPanel(frame: frame)
        let root = IslandView(state: state, model: model) { [weak self] id in
            self?.select(id)
        }
        let host = IslandHostView(layout: state.layout, rootView: root)
        host.currentSize = { [state] in state.currentSize }
        host.onHoverChange = { [weak self] hovering in self?.hoverChanged(hovering) }
        host.onRightClick = { [weak self] event in self?.showContextMenu(for: event) }
        host.onBackgroundClick = { [weak self] in self?.togglePinned() }
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        self.host = host

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reanchor() }
        }

        KeyboardShortcuts.onKeyUp(for: .toggleIsland) { [weak self] in
            self?.togglePinned()
        }
    }

    // MARK: - State machine

    private func hoverChanged(_ hovering: Bool) {
        self.hovering = hovering
        dwellTask?.cancel()
        if hovering {
            guard state.mode == .compact else { return }
            dwellTask = Task { [weak self] in
                try? await Task.sleep(for: Motion.hoverDwell)
                guard !Task.isCancelled, let self else { return }
                self.setMode(.expanded)
            }
        } else if !state.pinned {
            setMode(.compact)
        }
    }

    private func select(_ id: ProviderID?) {
        if let id {
            setMode(.detail(id))
        } else {
            setMode(.expanded)
        }
    }

    /// Pin open (from any state) or unpin and collapse.
    func togglePinned() {
        if state.pinned {
            state.pinned = false
            stopOutsideClickMonitor()
            if !hovering { setMode(.compact) }
        } else {
            state.pinned = true
            if state.mode == .compact { setMode(.expanded) }
            startOutsideClickMonitor()
        }
    }

    private func setMode(_ mode: IslandMode) {
        guard state.mode != mode else { return }
        withAnimation(Motion.island) {
            state.mode = mode
        }
        host?.refreshHover()
    }

    /// While pinned, a click anywhere else on screen unpins. Global mouse monitors need no
    /// special permission, unlike key monitors.
    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.state.pinned, let panel = self.panel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.togglePinned()
                }
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    // MARK: - Screen changes

    private func reanchor() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let panel else { return }
        let anchor = IslandGeometry.anchor(for: screen)
        let layout = IslandLayout.make(for: anchor)
        state.layout = layout
        host?.layout = layout
        panel.setFrame(IslandGeometry.panelFrame(layout: layout, on: screen), display: true)
    }

    // MARK: - Context menu

    private func showContextMenu(for event: NSEvent) {
        guard let host else { return }
        let menu = NSMenu()

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let pin = NSMenuItem(title: state.pinned ? "Unpin" : "Pin Open", action: #selector(pinFromMenu), keyEquivalent: "")
        pin.target = self
        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleIsland) {
            pin.keyEquivalent = shortcut.nsMenuItemKeyEquivalent ?? ""
            pin.keyEquivalentModifierMask = shortcut.modifiers
        }
        menu.addItem(pin)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Headroom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        NSMenu.popUpContextMenu(menu, with: event, for: host)
    }

    @objc private func refreshNow() { model.refreshAll() }
    @objc private func pinFromMenu() { togglePinned() }
    @objc private func openSettings() { onOpenSettings() }
}
