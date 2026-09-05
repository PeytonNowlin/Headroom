import AppKit
import SwiftUI

/// Hosts the SwiftUI island and owns hover tracking. Hit-testing is clipped to the island
/// silhouette for the current mode, so the transparent margins of the panel are inert; inside
/// the silhouette, SwiftUI receives clicks normally and unhandled ones bubble up here.
@MainActor
final class IslandHostView: NSView {
    private let hosting: NSHostingView<IslandView>
    private var trackingArea: NSTrackingArea?

    var layout: IslandLayout
    var currentSize: () -> CGSize = { .zero }
    var onHoverChange: (Bool) -> Void = { _ in }
    var onRightClick: (NSEvent) -> Void = { _ in }
    /// A left click inside the silhouette that no SwiftUI control consumed.
    var onBackgroundClick: () -> Void = {}

    private var hovering = false {
        didSet { if hovering != oldValue { onHoverChange(hovering) } }
    }

    init(layout: IslandLayout, rootView: IslandView) {
        self.layout = layout
        hosting = NSHostingView(rootView: rootView)
        super.init(frame: CGRect(origin: .zero, size: layout.panel))
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.isOpaque = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        hosting.layer?.isOpaque = false
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // `.inVisibleRect` tracks the whole visible bounds, so the area never needs rebuilding.
        // Rebuilding it on every layout pass (SwiftUI lays out on each countdown tick) makes
        // AppKit emit exit/enter pairs under a stationary cursor, which flaps the island.
        guard trackingArea == nil else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func islandContains(_ point: CGPoint) -> Bool {
        let rect = IslandGeometry.islandRect(layout: layout, size: currentSize())
        guard rect.contains(point) else { return false }
        let shape = IslandShape(cornerRadius: layout.cornerRadius, flare: layout.flare)
        return shape.path(in: rect).contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard islandContains(local) else { return nil }
        return hosting.hitTest(local) ?? self
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = islandContains(convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        hovering = islandContains(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        // Trust the cursor's real position over the event: exits can arrive while it's still inside.
        hovering = cursorInsideIsland()
    }

    private func cursorInsideIsland() -> Bool {
        guard let window else { return false }
        return islandContains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard islandContains(local) else { return }
        onBackgroundClick()
    }

    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard islandContains(local) else { return }
        onRightClick(event)
    }

    /// Re-evaluate hover after the island changes size under a stationary cursor.
    func refreshHover() {
        hovering = cursorInsideIsland()
    }
}
