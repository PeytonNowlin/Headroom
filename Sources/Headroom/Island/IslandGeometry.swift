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

    /// Horizontal gap between the main gauges and the side gauges.
    var compactGap: CGFloat {
        switch self {
        case let .notch(width, _): width
        case .simulatedNotch: 18
        }
    }
}

enum IslandMode: Equatable {
    /// Nothing to say: no silhouette, no glass, no pixels. Hovering the notch still summons it.
    case dormant
    case compact
    case expanded
    case detail(ProviderID)

    /// Either collapsed band state. Both expand on hover and neither takes keyboard focus.
    var isCompact: Bool { self == .compact || self == .dormant }

    var detailProvider: ProviderID? {
        if case let .detail(id) = self { return id }
        return nil
    }
}

/// The compact band's gauge metrics, in one place so the view and the hit-testing cannot drift.
/// Main gauges sit left of the notch at full size; side gauges sit right of it, smaller.
enum CompactMetrics {
    static let mainSize: CGFloat = 16
    static let secondarySize: CGFloat = 13
    static let spacing: CGFloat = 5
    /// Clearance between the notch edge and the nearest gauge.
    static let notchInset: CGFloat = 8
    /// Clearance between the outermost gauge and the end of the band.
    static let outerInset: CGFloat = 10

    static func groupWidth(count: Int, size: CGFloat) -> CGFloat {
        count <= 0 ? 0 : CGFloat(count) * size + CGFloat(count - 1) * spacing
    }
}

/// The runtime inputs to the island's size: how many gauges each side of the notch carries, and
/// the measured heights of the expanded and detail content.
struct IslandContent: Equatable {
    var mainGauges = 0
    var secondaryGauges = 0
    var expandedHeight: CGFloat = 250
    var detailHeight: CGFloat = 300
}

/// Fixed dimensions of the island, derived from the anchor. Detail height is content-driven
/// and supplied by the state.
struct IslandLayout: Equatable {
    var anchor: IslandAnchor
    var compact: CGSize
    var expandedWidth: CGFloat
    /// Horizontal distance the top corners flare outward to meet the bezel.
    var flare: CGFloat
    var cornerRadius: CGFloat

    /// Tallest the island can ever be; the panel is sized to this so it never resizes.
    static let maxHeight: CGFloat = 640

    /// Total panel size: the union of every mode.
    var panel: CGSize { CGSize(width: expandedWidth + flare * 2, height: Self.maxHeight) }

    /// Every size is content-driven: the band grows to hold its gauges rather than clipping
    /// them, and an island with no side providers is not padded out for a row that isn't there.
    func size(for mode: IslandMode, content: IslandContent) -> CGSize {
        let ceiling = Self.maxHeight - 110
        return switch mode {
        // Zero height, not a hidden or masked island: the glass layer stays in the hierarchy
        // untouched (see IslandView) and simply has nothing to draw.
        case .dormant: CGSize(width: compact.width, height: 0)
        case .compact: compactSize(main: content.mainGauges, secondary: content.secondaryGauges)
        case .expanded: CGSize(width: expandedWidth, height: min(max(content.expandedHeight, 120), ceiling))
        case .detail: CGSize(width: expandedWidth, height: min(content.detailHeight, ceiling))
        }
    }

    /// The band, symmetric about the notch and wide enough for whichever side carries more.
    /// Never narrower than the base band, so a single gauge still reads as part of the bezel.
    func compactSize(main: Int, secondary: Int) -> CGSize {
        let widest = max(CompactMetrics.groupWidth(count: main, size: CompactMetrics.mainSize),
                         CompactMetrics.groupWidth(count: secondary, size: CompactMetrics.secondarySize))
        let half = max((compact.width - anchor.compactGap) / 2,
                       widest + CompactMetrics.notchInset + CompactMetrics.outerInset)
        return CGSize(width: anchor.compactGap + half * 2, height: compact.height)
    }

    static func make(for anchor: IslandAnchor) -> IslandLayout {
        switch anchor {
        case let .notch(width, height):
            return IslandLayout(
                anchor: anchor,
                compact: CGSize(width: width + 2 * 46, height: height),
                expandedWidth: max(440, width + 2 * 46),
                flare: 12,
                cornerRadius: 14
            )
        case let .simulatedNotch(height):
            return IslandLayout(
                anchor: anchor,
                compact: CGSize(width: anchor.compactGap + 2 * 46, height: height),
                expandedWidth: 440,
                flare: 12,
                cornerRadius: 14
            )
        }
    }
}

enum IslandGeometry {
    /// Mirrors the compact HStacks: main gauges packed right-to-left against the notch's left
    /// edge, side gauges left-to-right against its right edge.
    static func compactProvider(at point: CGPoint, layout: IslandLayout,
                                main: [ProviderID], secondary: [ProviderID]) -> ProviderID? {
        let height = layout.compact.height
        let center = layout.panel.width / 2
        var x = center - layout.anchor.compactGap / 2 - CompactMetrics.notchInset
        for provider in main.reversed() {
            let size = CompactMetrics.mainSize
            let rect = CGRect(x: x - size, y: (height - size) / 2, width: size, height: size)
            if rect.contains(point) { return provider }
            x -= size + CompactMetrics.spacing
        }
        x = center + layout.anchor.compactGap / 2 + CompactMetrics.notchInset
        for provider in secondary {
            let size = CompactMetrics.secondarySize
            let rect = CGRect(x: x, y: (height - size) / 2, width: size, height: size)
            if rect.contains(point) { return provider }
            x += size + CompactMetrics.spacing
        }
        return nil
    }

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

    /// Where the cursor counts as "at the island". A dormant island has no silhouette to hover,
    /// so the notch band always answers — that is how you summon it when it is drawing nothing.
    static func hoverZone(layout: IslandLayout, size: CGSize) -> CGRect {
        let band = CGRect(x: (layout.panel.width - layout.compact.width) / 2, y: 0,
                          width: layout.compact.width, height: layout.compact.height)
        return band.union(islandRect(layout: layout, size: size))
    }
}
