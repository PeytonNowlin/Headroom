import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let island = IslandController()
        island.show()
        self.island = island
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
