import AppKit

/// Where the island hangs from on the current main display.
enum IslandAnchor: Equatable {
    /// The screen has a hardware notch; the island grows out of it.
    case notch(width: CGFloat, height: CGFloat)
    /// No notch; the island is a pill just below the menu bar.
    case pill(menuBarHeight: CGFloat)

    var isNotch: Bool {
        if case .notch = self { return true }
        return false
    }
}

/// Fixed dimensions of the island in each mode, derived from the anchor.
struct IslandLayout: Equatable {
    var anchor: IslandAnchor
    var compact: CGSize
    var expanded: CGSize
    /// Horizontal distance the top corners flare outward to meet the bezel.
    var flare: CGFloat
    var cornerRadius: CGFloat
    /// Total panel size: the union of every mode so the panel never needs to resize.
    var panel: CGSize { CGSize(width: expanded.width + flare * 2, height: expanded.height) }

    func size(for mode: IslandMode) -> CGSize {
        switch mode {
        case .compact: compact
        case .expanded: expanded
        }
    }

    static let expandedSize = CGSize(width: 360, height: 176)

    static func make(for anchor: IslandAnchor) -> IslandLayout {
        switch anchor {
        case let .notch(width, height):
            return IslandLayout(
                anchor: anchor,
                compact: CGSize(width: width + 2 * 46, height: height),
                expanded: CGSize(width: max(expandedSize.width, width + 2 * 46), height: expandedSize.height),
                flare: 12,
                cornerRadius: 14
            )
        case .pill:
            return IslandLayout(
                anchor: anchor,
                compact: CGSize(width: 132, height: 30),
                expanded: expandedSize,
                flare: 0,
                cornerRadius: 15
            )
        }
    }
}

enum IslandMode: Equatable {
    case compact
    case expanded
}

enum IslandGeometry {
    static func anchor(for screen: NSScreen) -> IslandAnchor {
        let inset = screen.safeAreaInsets.top
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return .notch(width: width, height: inset)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return .pill(menuBarHeight: max(menuBar, 24))
    }

    /// Panel frame in screen coordinates: top-center, flush with the top edge for a notch,
    /// tucked under the menu bar for a pill.
    static func panelFrame(layout: IslandLayout, on screen: NSScreen) -> CGRect {
        let size = layout.panel
        let x = screen.frame.midX - size.width / 2
        let top: CGFloat
        switch layout.anchor {
        case .notch:
            top = screen.frame.maxY
        case let .pill(menuBarHeight):
            top = screen.frame.maxY - menuBarHeight - 6
        }
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    /// The island's rect inside the panel for a given mode, in a top-left-origin coordinate space.
    static func islandRect(layout: IslandLayout, mode: IslandMode) -> CGRect {
        let size = layout.size(for: mode)
        let panel = layout.panel
        return CGRect(x: (panel.width - size.width) / 2, y: 0, width: size.width, height: size.height)
    }
}
