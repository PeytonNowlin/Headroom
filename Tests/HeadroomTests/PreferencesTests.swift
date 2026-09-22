import Foundation
import HeadroomCore
import Testing
@testable import Headroom

@Suite("Preferences migration", .serialized)
@MainActor
struct PreferencesTests {
    @Test("tiers default sensibly and an older install's hidden providers stay hidden")
    func tiers() throws {
        let name = "HeadroomTierTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let fresh = Preferences(defaults: defaults)
        #expect(fresh.tier(.claude) == .main)
        #expect(fresh.tier(.codex) == .main)
        for id in [ProviderID.grok, .cursor, .opencode] { #expect(fresh.tier(id) == .secondary) }

        // A provider hidden before tiers existed must not reappear as a side provider.
        let legacy = Data(#"{"visibility":["claude","hide"],"order":["codex","claude","cursor","grok","opencode"],"hideInFullScreen":false,"showMenuBarIcon":false,"didRegisterLoginItem":true,"didCompleteFirstRun":true}"#.utf8)
        defaults.set(legacy, forKey: "headroom.preferences")
        let migrated = Preferences(defaults: defaults)
        #expect(migrated.tier(.claude) == .hidden)
        #expect(migrated.tier(.codex) == .main)
        #expect(migrated.tier(.grok) == .secondary)

        migrated.setTier(.main, for: .opencode)
        migrated.setTier(.secondary, for: .codex)
        let restored = Preferences(defaults: defaults)
        #expect(restored.tier(.opencode) == .main)
        #expect(restored.tier(.codex) == .secondary)
        // An explicit tier wins over the legacy hide.
        migrated.setTier(.main, for: .claude)
        #expect(Preferences(defaults: defaults).tier(.claude) == .main)
    }

    @Test("existing preferences survive the addition of alert settings")
    func migration() throws {
        let name = "HeadroomTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = Data(#"{"visibility":["claude","hide"],"order":["codex","claude","cursor","grok"],"hideInFullScreen":true,"showMenuBarIcon":true,"didRegisterLoginItem":true,"didCompleteFirstRun":true}"#.utf8)
        defaults.set(legacy, forKey: "headroom.preferences")
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.order.first == .codex)
        #expect(preferences.tier(.claude) == .hidden)
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
        #expect(restored.tier(.claude) == .hidden)
    }
}
