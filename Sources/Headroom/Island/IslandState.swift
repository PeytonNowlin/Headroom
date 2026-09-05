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
    var keyboardNavigation = false
    var focusedProvider: ProviderID?

    func moveProviderFocus(_ delta: Int, providers: [ProviderID]) {
        guard !providers.isEmpty else { focusedProvider = nil; return }
        let index = focusedProvider.flatMap { providers.firstIndex(of: $0) } ?? (delta > 0 ? -1 : 0)
        focusedProvider = providers[(index + delta + providers.count) % providers.count]
        keyboardNavigation = true
    }
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
