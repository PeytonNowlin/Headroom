import AppKit
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
        let host = IslandHostView(layout: state.layout, rootView: IslandView(state: state, model: model))
        host.currentMode = { [state] in state.mode }
        host.onHoverChange = { [weak self] hovering in self?.hoverChanged(hovering) }
        host.onRightClick = { [weak self] event in self?.showContextMenu(for: event) }
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
    }

    // MARK: - Hover state machine

    private func hoverChanged(_ hovering: Bool) {
        dwellTask?.cancel()
        if hovering {
            guard state.mode == .compact else { return }
            dwellTask = Task { [weak self] in
                try? await Task.sleep(for: Motion.hoverDwell)
                guard !Task.isCancelled, let self else { return }
                self.setMode(.expanded)
            }
        } else {
            setMode(.compact)
        }
    }

    private func setMode(_ mode: IslandMode) {
        guard state.mode != mode else { return }
        withAnimation(Motion.island) {
            state.mode = mode
        }
        host?.refreshHover()
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
        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Headroom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSMenu.popUpContextMenu(menu, with: event, for: host)
    }

    @objc private func refreshNow() {
        model.refreshAll()
    }
}
