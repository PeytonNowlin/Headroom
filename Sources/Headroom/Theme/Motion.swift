import AppKit
import SwiftUI

/// Animation curves, collapsing to short fades when Reduce Motion is on.
@MainActor
enum Motion {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var island: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    static var materialize: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .easeOut(duration: 0.4)
    }

    static var ringSweep: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .easeInOut(duration: 0.7)
    }

    static var lift: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.3, dampingFraction: 0.7)
    }

    static let hoverDwell: Duration = .milliseconds(150)
}
