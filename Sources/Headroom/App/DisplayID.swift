import AppKit

extension NSScreen {
    /// Stable identity for a display across `NSScreen` instances, which AppKit recreates whenever
    /// screen parameters change.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The screen's frame in Core Graphics global coordinates (origin at the top-left of the
    /// primary display, y growing downward), which is what `CGWindowListCopyWindowInfo` reports.
    var cgFrame: CGRect {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        return CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }
}
