import HeadroomCore
import Observation
import SwiftUI

@MainActor
@Observable
final class IslandState {
    var mode: IslandMode = .compact
    var layout: IslandLayout
    /// Pinned: stays open when the cursor leaves; cleared by click, hotkey, or clicking outside.
    var pinned = false
    /// Measured height of the detail content; drives the island size in `.detail`.
    var detailHeight: CGFloat = 300
    /// A full-screen app owns the active space. Glass can't sample its backdrop from a
    /// status-level panel (it renders black), so the island draws as solid bezel instead.
    var fullScreenActive = false

    init(layout: IslandLayout) {
        self.layout = layout
    }

    /// Body size of the island (excluding flares) for the current mode.
    var currentSize: CGSize {
        layout.size(for: mode, detailHeight: detailHeight)
    }
}
