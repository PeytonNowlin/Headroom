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
        // CG uses a top-left origin on the primary display. A native full-screen window spans the
        // width and stops below the notch band, so it is shorter than the screen by the top
        // safe-area inset; a zoomed window has the very same geometry. What separates them is the
        // menu bar: the WindowServer's menu bar window is on screen for a desktop and hidden
        // (off screen) for a full-screen space.
        let screenSize = screen.frame.size
        let minHeight = screenSize.height - screen.safeAreaInsets.top - 1
        var coveringWindow = false
        var menuBarVisible = false
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"], let y = bounds["Y"] else { continue }
            let owner = window[kCGWindowOwnerName as String] as? String
            if layer == NSWindow.Level.mainMenu.rawValue, owner == "Window Server",
               abs(w - screenSize.width) < 1, h <= 60, y > -0.5 {
                menuBarVisible = true
            }
            if layer == 0, (window[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
               abs(w - screenSize.width) < 1, h >= minHeight {
                coveringWindow = true
            }
        }
        return coveringWindow && !menuBarVisible
    }
}
