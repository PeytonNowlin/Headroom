import AppKit
import Observation
import Sparkle

/// Sparkle owns download validation, installation, and relaunch. Headroom only exposes its UI.
@MainActor
@Observable
final class UpdateController {
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    private(set) var canCheck = false
    private(set) var automaticallyChecks = false

    init() {
        // SwiftPM tests and command-line builds are not installable app bundles.
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in self?.canCheck = value }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor in self?.automaticallyChecks = value }
            },
        ]
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        guard canCheck else { return }
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}
