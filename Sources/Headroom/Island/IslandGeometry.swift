import AppKit
import HeadroomCore

/// Where the island hangs from on a given display. Either way it is a bezel-black band flush
/// with the top edge; the difference is whether a hardware notch sits inside it.
enum IslandAnchor: Equatable {
    /// The screen has a hardware notch; the island grows out of it and content skips its band.
    case notch(width: CGFloat, height: CGFloat)
    /// No hardware notch; the island draws a small one at the top center.
    case simulatedNotch(height: CGFloat)

    /// Height of the hardware notch that content must leave clear; zero when simulated.
    var notchHeight: CGFloat {
        if case let .notch(_, height) = self { return height }
        return 0
    }

    /// Horizontal gap between the two groups of compact dots.
    var compactGap: CGFloat {
        switch self {
        case let .notch(width, _): width
        case .simulatedNotch: 18
        }
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
        case let .simulatedNotch(height):
            return IslandLayout(
                anchor: anchor,
                compact: CGSize(width: anchor.compactGap + 2 * 46, height: height),
                expandedWidth: 360,
                expandedHeight: 216 - 33,
                flare: 12,
                cornerRadius: 14
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
        // Match the hardware notch's band height so islands look alike across displays; grow to
        // the menu bar if it happens to be taller.
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return .simulatedNotch(height: max(menuBar, 32))
    }

    /// Panel frame in screen coordinates: top-center, flush with the top edge.
    static func panelFrame(layout: IslandLayout, on screen: NSScreen) -> CGRect {
        let size = layout.panel
        let x = screen.frame.midX - size.width / 2
        let top = screen.frame.maxY
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    /// The island's rect inside the panel, in a top-left-origin coordinate space.
    static func islandRect(layout: IslandLayout, size: CGSize) -> CGRect {
        let panel = layout.panel
        let width = size.width + layout.flare * 2
        return CGRect(x: (panel.width - width) / 2, y: 0, width: width, height: size.height)
    }
}
