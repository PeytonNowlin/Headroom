import AppKit
import HeadroomCore

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

    var notchHeight: CGFloat {
        if case let .notch(_, height) = self { return height }
        return 0
    }

    var notchWidth: CGFloat {
        if case let .notch(width, _) = self { return width }
        return 0
    }
}

enum IslandMode: Equatable {
    case compact
    case expanded
    case detail(ProviderID)

    var isCompact: Bool { self == .compact }

    var detailProvider: ProviderID? {
        if case let .detail(id) = self { return id }
        return nil
    }
}

/// Fixed dimensions of the island, derived from the anchor. Detail height is content-driven
/// and supplied by the state.
struct IslandLayout: Equatable {
    var anchor: IslandAnchor
    var compact: CGSize
    var expandedWidth: CGFloat
    var expandedHeight: CGFloat
    /// Horizontal distance the top corners flare outward to meet the bezel.
    var flare: CGFloat
    var cornerRadius: CGFloat

    /// Tallest the island can ever be; the panel is sized to this so it never resizes.
    static let maxHeight: CGFloat = 480

    /// Total panel size: the union of every mode.
    var panel: CGSize { CGSize(width: expandedWidth + flare * 2, height: Self.maxHeight) }

    func size(for mode: IslandMode, detailHeight: CGFloat) -> CGSize {
        switch mode {
        case .compact: compact
        case .expanded: CGSize(width: expandedWidth, height: expandedHeight)
        case .detail: CGSize(width: expandedWidth, height: min(detailHeight, Self.maxHeight))
        }
    }

    static func make(for anchor: IslandAnchor) -> IslandLayout {
        switch anchor {
        case let .notch(width, height):
            return IslandLayout(
                anchor: anchor,
                compact: CGSize(width: width + 2 * 46, height: height),
                expandedWidth: max(360, width + 2 * 46),
                expandedHeight: 216,
                flare: 12,
                cornerRadius: 14
            )
        case .pill:
            return IslandLayout(
                anchor: anchor,
                compact: CGSize(width: 132, height: 30),
                expandedWidth: 360,
                expandedHeight: 216 - 33,
                flare: 0,
                cornerRadius: 15
            )
        }
    }
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

    /// The island's rect inside the panel, in a top-left-origin coordinate space.
    static func islandRect(layout: IslandLayout, size: CGSize) -> CGRect {
        let panel = layout.panel
        let width = size.width + layout.flare * 2
        return CGRect(x: (panel.width - width) / 2, y: 0, width: width, height: size.height)
    }
}
