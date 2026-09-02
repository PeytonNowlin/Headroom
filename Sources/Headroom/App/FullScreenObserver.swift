import AppKit

/// Reports whether the active space on the main display is a full-screen app. There is no
/// public API for this; the reliable tell is a foreign window at the normal layer whose bounds
/// equal the whole screen, checked on every space change.
@MainActor
final class FullScreenObserver {
    private var observers: [NSObjectProtocol] = []
    var onChange: (Bool) -> Void = { _ in }
    private(set) var isFullScreen = false

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            })
        }
        evaluate()
    }

    func evaluate() {
        let value = Self.detect()
        guard value != isFullScreen else { return }
        isFullScreen = value
        onChange(value)
    }

    private static func detect() -> Bool {
        guard let screen = NSScreen.main,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // CG uses a top-left origin on the primary display; compare sizes only to stay robust.
        // On a notched display a native full-screen window stops below the notch band, so it is
        // shorter than the screen by the top safe-area inset.
        let screenSize = screen.frame.size
        let minHeight = screenSize.height - screen.safeAreaInsets.top - 1
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"] else { continue }
            if abs(w - screenSize.width) < 1 && h >= minHeight {
                return true
            }
        }
        return false
    }
}
