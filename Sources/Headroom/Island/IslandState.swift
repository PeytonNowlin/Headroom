import HeadroomCore
import Observation
import SwiftUI

@MainActor
@Observable
final class IslandState {
    var mode: IslandMode = .compact
    var layout: IslandLayout
    /// Measured height of the detail content; drives the island size in `.detail`.
    var detailHeight: CGFloat = 300

    init(layout: IslandLayout) {
        self.layout = layout
    }

    /// Body size of the island (excluding flares) for the current mode.
    var currentSize: CGSize {
        layout.size(for: mode, detailHeight: detailHeight)
    }
}
