import Foundation
import HeadroomCore
import Testing
@testable import Headroom

/// The rule that makes the island worth having: it draws nothing until a main agent is near
/// its limit, and side providers never summon it on their own.
@Suite("Dormancy and tiers", .serialized)
@MainActor
struct DormancyTests {
    private func preferences() throws -> (Preferences, UserDefaults, String) {
        let suite = "HeadroomDormancy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (Preferences(defaults: defaults), defaults, suite)
    }

    @Test("nothing to say means nothing on screen")
    func healthyIsInvisible() throws {
        let (prefs, defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ModelFixture.model(used: [.claude: 10, .codex: 5, .opencode: 20], preferences: prefs)
        #expect(model.isDormant)
        #expect(model.compactMain.isEmpty)
        #expect(model.compactSecondary.isEmpty)
    }

    @Test("a side provider running low is not a reason to appear")
    func sideProviderStaysQuiet() throws {
        let (prefs, defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ModelFixture.model(used: [.claude: 10, .opencode: 98, .grok: 95], preferences: prefs)
        #expect(prefs.tier(.opencode) == .secondary)
        #expect(model.isDormant)
        #expect(model.compactSecondary.isEmpty)
    }

    @Test("a main agent past the first threshold brings the band up, side gauges with it")
    func mainProviderSpeaks() throws {
        let (prefs, defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ModelFixture.model(used: [.claude: 75, .codex: 5, .opencode: 98], preferences: prefs)
        #expect(!model.isDormant)
        #expect(model.compactMain == [.claude])
        #expect(model.compactSecondary == [.opencode])
        // Codex has room, so it gets no gauge even though it is a main agent.
        #expect(!model.compactMain.contains(.codex))
    }

    @Test("an expired main login speaks even with quota to spare")
    func brokenLoginSpeaks() throws {
        let (prefs, defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ModelFixture.model(used: [.claude: 1], preferences: prefs, expired: [.codex])
        #expect(!model.isDormant)
        #expect(model.compactMain == [.codex])
    }

    @Test("promoting a side provider makes it able to summon the island")
    func promotingChangesWhoSpeaks() throws {
        let (prefs, defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ModelFixture.model(used: [.claude: 10, .opencode: 98], preferences: prefs)
        #expect(model.isDormant)
        prefs.setTier(.main, for: .opencode)
        #expect(!model.isDormant)
        #expect(model.compactMain == [.opencode])
        prefs.setTier(.hidden, for: .opencode)
        #expect(model.isDormant)
        #expect(!model.visibleProviders.contains(.opencode))
    }

    @Test("a provider you are not signed in to is never drawn")
    func unknownProvidersAreNotDrawn() throws {
        let (prefs, defaults, suite) = try preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ModelFixture.model(used: [.claude: 95], preferences: prefs)
        #expect(model.visibleProviders == [.claude])
        #expect(!model.visibleProviders.contains(.cursor))
    }
}
