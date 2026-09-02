import AppKit
import HeadroomCore
import KeyboardShortcuts
import SwiftUI

/// Owns one island per display and the behaviour they share: pinning, the global hotkey, and
/// tracking displays as they come and go. Hover and mode are per island (see `IslandInstance`).
@MainActor
final class IslandController {
    private let model: UsageModel
    private var instances: [CGDirectDisplayID: IslandInstance] = [:]
    private var pinned = false
    private var hiddenDisplays: Set<CGDirectDisplayID> = []
    private var screenObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?

    var onOpenSettings: () -> Void = {}

    init(model: UsageModel) {
        self.model = model
    }

    func show() {
        syncScreens()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreens() }
        }
        // After wake the WindowServer can report stale geometry for a beat and leave a
        // status-level panel behind other windows; re-anchor twice and re-order front.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncScreens()
                try? await Task.sleep(for: .seconds(2))
                self?.syncScreens()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .toggleIsland) { [weak self] in
            self?.togglePinned()
        }
    }

    // MARK: - Displays

    /// Reconcile islands with the current set of displays: re-anchor the ones that remain, add
    /// one for each new display, drop the ones whose display is gone.
    private func syncScreens() {
        var seen: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            seen.insert(id)
            if let instance = instances[id] {
                instance.reanchor(to: screen)
            } else {
                instances[id] = makeInstance(on: screen)
            }
        }
        for id in Set(instances.keys).subtracting(seen) {
            instances.removeValue(forKey: id)?.close()
        }
    }

    private func makeInstance(on screen: NSScreen) -> IslandInstance {
        let id = screen.displayID ?? 0
        let layout = IslandLayout.make(for: IslandGeometry.anchor(for: screen))
        let state = IslandState(layout: layout)
        state.pinned = pinned
        let root = IslandView(
            state: state, model: model,
            onSelect: { [weak self] provider in self?.select(provider, on: id) },
            onOpenSettings: { [weak self] in self?.onOpenSettings() }
        )
        let host = IslandHostView(layout: layout, rootView: root)
        host.currentSize = { [state] in state.currentSize }
        host.onHoverChange = { [weak self] hovering in self?.hoverChanged(hovering, on: id) }
        host.onRightClick = { [weak self] event in self?.showContextMenu(for: event, on: id) }
        host.onBackgroundClick = { [weak self] in self?.togglePinned() }
        let panel = IslandPanel(frame: IslandGeometry.panelFrame(layout: layout, on: screen))
        panel.contentView = host

        let instance = IslandInstance(displayID: id, state: state, panel: panel, host: host)
        instance.setHidden(hiddenDisplays.contains(id))
        if pinned { instance.setMode(.expanded) }
        return instance
    }

    // MARK: - State machine

    private func hoverChanged(_ hovering: Bool, on id: CGDirectDisplayID) {
        guard let instance = instances[id] else { return }
        instance.hovering = hovering
        instance.dwellTask?.cancel()
        if hovering {
            guard instance.state.mode == .compact else { return }
            instance.dwellTask = Task { [weak instance] in
                try? await Task.sleep(for: Motion.hoverDwell)
                guard !Task.isCancelled, let instance else { return }
                instance.setMode(.expanded)
            }
        } else if !pinned {
            // Brief grace so a re-entry a few milliseconds later cancels the collapse instead of
            // interrupting the expand transition midway.
            instance.dwellTask = Task { [weak self, weak instance] in
                try? await Task.sleep(for: Motion.collapseGrace)
                guard !Task.isCancelled, let self, let instance, !instance.hovering, !self.pinned else { return }
                instance.setMode(.compact)
            }
        }
    }

    private func select(_ provider: ProviderID?, on id: CGDirectDisplayID) {
        guard let instance = instances[id] else { return }
        if let provider {
            instance.setMode(.detail(provider))
        } else {
            instance.setMode(.expanded)
        }
    }

    /// Pin every island open (from any state) or unpin them all and collapse.
    func togglePinned() {
        pinned.toggle()
        for instance in instances.values {
            instance.state.pinned = pinned
            if pinned {
                if instance.state.mode == .compact { instance.setMode(.expanded) }
            } else if !instance.hovering {
                instance.setMode(.compact)
            }
        }
        if pinned {
            startOutsideClickMonitor()
        } else {
            stopOutsideClickMonitor()
        }
    }

    /// While pinned, a click anywhere outside every island unpins. Global mouse monitors need no
    /// special permission, unlike key monitors.
    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.pinned else { return }
                let location = NSEvent.mouseLocation
                if !self.instances.values.contains(where: { $0.panel.frame.contains(location) }) {
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

    /// First launch with nothing detected: open with guidance for a moment, then collapse.
    func showFirstRunGuidance() {
        guard !pinned else { return }
        for instance in instances.values { instance.setMode(.expanded) }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !self.pinned else { return }
            for instance in self.instances.values where !instance.hovering {
                instance.setMode(.compact)
            }
        }
    }

    // MARK: - Context menu

    private func showContextMenu(for event: NSEvent, on id: CGDirectDisplayID) {
        guard let instance = instances[id] else { return }
        let menu = NSMenu()

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let pin = NSMenuItem(title: pinned ? "Unpin" : "Pin Open", action: #selector(pinFromMenu), keyEquivalent: "")
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

        NSMenu.popUpContextMenu(menu, with: event, for: instance.host)
    }

    /// Hide the islands on the given displays (full-screen spaces) and show the rest.
    func setHidden(on displays: Set<CGDirectDisplayID>) {
        hiddenDisplays = displays
        for (id, instance) in instances {
            instance.setHidden(displays.contains(id))
        }
    }

    @objc private func refreshNow() { model.refreshAll() }
    @objc private func pinFromMenu() { togglePinned() }
    @objc private func openSettings() { onOpenSettings() }
}
