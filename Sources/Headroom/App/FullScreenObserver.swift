import AppKit

/// Reports which displays currently show a full-screen app. There is no public API for this;
/// infer it from normal-layer windows covering a display with no visible menu bar,
/// checked on every space change.
@MainActor
final class FullScreenObserver {
    private var observers: [NSObjectProtocol] = []
    var onChange: (Set<CGDirectDisplayID>) -> Void = { _ in }
    private(set) var fullScreenDisplays: Set<CGDirectDisplayID> = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        })
        evaluate()
    }

    func evaluate() {
        let value = Self.detect()
        guard value != fullScreenDisplays else { return }
        fullScreenDisplays = value
        onChange(value)
    }

    private static func detect() -> Set<CGDirectDisplayID> {
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        // With separate Spaces each display has its own menu bar, which hides only on that
        // display. Without them there is one menu bar, on the primary display, and it hides when
        // any display goes full screen.
        let separateSpaces = NSScreen.screensHaveSeparateSpaces
        var result: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            if isFullScreen(screen, menuBarScreen: separateSpaces ? screen : primary, windows: windows) {
                result.insert(id)
            }
        }
        return result
    }

    private static func isFullScreen(_ screen: NSScreen, menuBarScreen: NSScreen, windows: [[String: Any]]) -> Bool {
        isFullScreen(frame: screen.cgFrame, menuFrame: menuBarScreen.cgFrame,
                     inset: screen.safeAreaInsets.top, windows: windows)
    }

    static func isFullScreen(frame: CGRect, menuFrame: CGRect, inset: CGFloat, windows: [[String: Any]]) -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // A native full-screen window spans the display's width and stops below the notch band,
        // so it is shorter than the display by the top safe-area inset; a zoomed window has the
        // very same geometry. What separates them is the menu bar: the WindowServer's menu bar
        // window is on screen for a desktop and moved off screen for a full-screen space.
        var bandsByOwner: [pid_t: [CGRect]] = [:]
        var menuBarVisible = false
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = bounds["Width"], let h = bounds["Height"],
                  let x = bounds["X"], let y = bounds["Y"] else { continue }
            let owner = window[kCGWindowOwnerName as String] as? String
            if layer == NSWindow.Level.mainMenu.rawValue, owner == "Window Server",
               abs(w - menuFrame.width) < 1, h <= 60,
               abs(x - menuFrame.minX) < 1, y > menuFrame.minY - 0.5, y < menuFrame.minY + 60 {
                menuBarVisible = true
            }
            if layer == 0, let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
               abs(w - frame.width) < 1, abs(x - frame.minX) < 1, h > 0,
               y >= frame.minY - 0.5, y < frame.maxY {
                bandsByOwner[pid, default: []].append(CGRect(x: x, y: y, width: w, height: h))
            }
        }
        guard !menuBarVisible else { return false }
        // Chrome can expose its full-screen toolbar and content as separate windows.
        // Require continuous coverage from one process; unrelated apps and gaps do not count.
        return bandsByOwner.values.contains { bands in
            var coveredTo = frame.minY + inset
            for band in bands.sorted(by: { $0.minY < $1.minY }) {
                guard band.minY <= coveredTo + 0.5 else { return false }
                coveredTo = max(coveredTo, band.maxY)
                if coveredTo >= frame.maxY - 1 { return true }
            }
            return false
        }
    }
}
