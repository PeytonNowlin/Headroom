import AppKit
import Testing
@testable import Headroom

@MainActor
struct FullScreenObserverTests {
    private let frame = CGRect(x: 1920, y: 163, width: 1920, height: 1080)

    private func window(y: CGFloat, height: CGFloat, pid: pid_t = -1, layer: Int = 0, owner: String = "Google Chrome") -> [String: Any] {
        [kCGWindowLayer as String: layer, kCGWindowOwnerPID as String: pid,
         kCGWindowOwnerName as String: owner,
         kCGWindowBounds as String: ["X": CGFloat(1920), "Y": y, "Width": CGFloat(1920), "Height": height]]
    }

    @Test("Chrome full-screen toolbar and content windows jointly cover the display")
    func chromeFullScreen() {
        // WindowServer geometry captured while Chrome was full screen and Headroom remained visible.
        let windows = [window(y: 163, height: 41), window(y: 204, height: 81),
                       window(y: 163, height: 158), window(y: 285, height: 958)]
        #expect(FullScreenObserver.isFullScreen(frame: frame, menuFrame: frame, inset: 0, windows: windows))
    }

    @Test("a visible menu bar keeps a maximized Chrome window visible")
    func desktopMenuBar() {
        let windows = [window(y: 163, height: 122), window(y: 285, height: 958),
                       window(y: 163, height: 24, pid: -2, layer: NSWindow.Level.mainMenu.rawValue, owner: "Window Server")]
        #expect(!FullScreenObserver.isFullScreen(frame: frame, menuFrame: frame, inset: 0, windows: windows))
    }

    @Test("gaps and windows from different apps cannot complete coverage")
    func incompleteCoverage() {
        for windows in [
            [window(y: 163, height: 100), window(y: 285, height: 958)],
            [window(y: 163, height: 122, pid: -2), window(y: 285, height: 958)],
            [window(y: 285, height: 958)]
        ] {
            #expect(!FullScreenObserver.isFullScreen(frame: frame, menuFrame: frame, inset: 0, windows: windows))
        }
    }

    @Test("single full-screen windows still support displays with and without a notch")
    func singleWindow() {
        for inset: CGFloat in [0, 37] {
            #expect(FullScreenObserver.isFullScreen(frame: frame, menuFrame: frame, inset: inset,
                windows: [window(y: 163 + inset, height: 1080 - inset)]))
        }
        #expect(!FullScreenObserver.isFullScreen(frame: frame, menuFrame: frame, inset: 0,
            windows: [window(y: 163, height: 1080, pid: ProcessInfo.processInfo.processIdentifier)]))
    }

}
