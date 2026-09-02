import AppKit
import HeadroomCore
import SwiftUI

/// One island on one display: its panel, host view, and the state the view renders. Mode and
/// hover are per display because the cursor is only ever on one; pinning is shared across
/// displays and pushed in by the controller.
@MainActor
final class IslandInstance {
    let displayID: CGDirectDisplayID
    let state: IslandState
    let panel: IslandPanel
    let host: IslandHostView
    var dwellTask: Task<Void, Never>?
    var hovering = false
    private var hiddenForFullScreen = false

    init(displayID: CGDirectDisplayID, state: IslandState, panel: IslandPanel, host: IslandHostView) {
        self.displayID = displayID
        self.state = state
        self.panel = panel
        self.host = host
    }

    /// Recompute layout and frame for the screen's current geometry and bring the panel back
    /// to the front unless a full-screen space owns this display.
    func reanchor(to screen: NSScreen) {
        let layout = IslandLayout.make(for: IslandGeometry.anchor(for: screen))
        if layout != state.layout {
            state.layout = layout
            host.layout = layout
        }
        panel.setFrame(IslandGeometry.panelFrame(layout: layout, on: screen), display: true)
        if !hiddenForFullScreen { panel.orderFrontRegardless() }
    }

    func setMode(_ mode: IslandMode) {
        guard state.mode != mode else { return }
        HeadroomLog.polling.debug("island[\(self.displayID)] mode -> \(String(describing: mode), privacy: .public)")
        withAnimation(Motion.island) {
            state.mode = mode
        }
        host.refreshHover()
    }

    /// Hide/show for full-screen spaces without tearing down state.
    func setHidden(_ hidden: Bool) {
        hiddenForFullScreen = hidden
        if hidden {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// The display went away; drop the panel.
    func close() {
        dwellTask?.cancel()
        panel.close()
    }
}
