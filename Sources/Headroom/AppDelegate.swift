import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?
    private var model: UsageModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = UsageModel()
        let island = IslandController(model: model)
        island.show()
        model.start()
        self.model = model
        self.island = island
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
