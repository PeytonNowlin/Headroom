import Foundation
import HeadroomCore
import Testing
@testable import Headroom

@Suite("Preferences migration", .serialized)
@MainActor
struct PreferencesTests {
    @Test("existing preferences survive the addition of alert settings")
    func migration() throws {
        let name = "HeadroomTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = Data(#"{"visibility":["claude","hide"],"order":["codex","claude","cursor","grok"],"hideInFullScreen":true,"showMenuBarIcon":true,"didRegisterLoginItem":true,"didCompleteFirstRun":true}"#.utf8)
        defaults.set(legacy, forKey: "headroom.preferences")
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.order.first == .codex)
        #expect(preferences.visibility(.claude) == .hide)
        #expect(preferences.hideInFullScreen)
        #expect(preferences.showMenuBarIcon)
        #expect(preferences.didCompleteFirstRun)
        #expect(preferences.alertOptions(.claude).warningsEnabled)
        #expect(!preferences.alertOptions(.claude).notifyOnReset)

        var options = preferences.alertOptions(.claude)
        options.warningsEnabled = false
        options.notifyOnReset = true
        preferences.setAlertOptions(options, for: .claude)
        let restored = Preferences(defaults: defaults)
        #expect(restored.alertOptions(.claude) == options)
        #expect(restored.alertOptions(.codex).warningsEnabled)
        #expect(restored.order == preferences.order)
        #expect(restored.visibility(.claude) == .hide)
    }
}
