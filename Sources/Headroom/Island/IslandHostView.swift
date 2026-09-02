import AppKit
import SwiftUI

/// Hosts the SwiftUI island and owns all mouse input. Hover and hit-testing are clipped to the
/// island silhouette for the current mode, so the transparent margins of the panel are inert.
@MainActor
final class IslandHostView: NSView {
    private let hosting: NSHostingView<IslandView>
    private var trackingArea: NSTrackingArea?

    var layout: IslandLayout
    var currentMode: () -> IslandMode = { .compact }
    var onHoverChange: (Bool) -> Void = { _ in }
    var onClick: (CGPoint) -> Void = { _ in }
    var onRightClick: (NSEvent) -> Void = { _ in }

    private var hovering = false {
        didSet { if hovering != oldValue { onHoverChange(hovering) } }
    }

    init(layout: IslandLayout, rootView: IslandView) {
        self.layout = layout
        hosting = NSHostingView(rootView: rootView)
        super.init(frame: CGRect(origin: .zero, size: layout.panel))
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

    var rootView: IslandView {
        get { hosting.rootView }
        set { hosting.rootView = newValue }
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
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
        let rect = IslandGeometry.islandRect(layout: layout, mode: currentMode())
        guard rect.contains(point) else { return false }
        let shape = IslandShape(cornerRadius: layout.cornerRadius, flare: layout.flare)
        return shape.path(in: rect).contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return islandContains(local) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = islandContains(convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        hovering = islandContains(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard islandContains(local) else { return }
        onClick(local)
    }

    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard islandContains(local) else { return }
        onRightClick(event)
    }

    /// Re-evaluate hover after the island changes size under a stationary cursor.
    func refreshHover() {
        guard let window else { return }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        hovering = islandContains(convert(windowPoint, from: nil))
    }
}
