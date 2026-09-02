import Observation
import SwiftUI

@MainActor
@Observable
final class IslandState {
    var mode: IslandMode = .compact
    var layout: IslandLayout

    init(layout: IslandLayout) {
        self.layout = layout
    }
}
