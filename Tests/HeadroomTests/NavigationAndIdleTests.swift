import Foundation
import HeadroomCore
import Testing
@testable import Headroom

@Suite("Keyboard and idle policy", .serialized)
@MainActor
struct NavigationAndIdleTests {
    @Test("provider focus follows order, wraps, and handles disappearing providers")
    func navigation() {
        let state = IslandState(layout: .make(for: .simulatedNotch(height: 32)))
        state.moveProviderFocus(1, providers: [.codex, .claude, .cursor])
        #expect(state.focusedProvider == .codex)
        #expect(state.keyboardNavigation)
        state.moveProviderFocus(-1, providers: [.codex, .claude, .cursor])
        #expect(state.focusedProvider == .cursor)
        state.moveProviderFocus(1, providers: [.codex, .claude])
        #expect(state.focusedProvider == .codex)
        state.moveProviderFocus(1, providers: [])
        #expect(state.focusedProvider == nil)
    }

    @Test("fast countdowns run only while at least one surface is visible")
    func visibility() throws {
        let name = "HeadroomIdleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let environment = HostEnvironment(home: URL(filePath: "/tmp/headroom-idle-test"), timeZone: .gmt,
                                          readFile: { _ in Data() }, fileExists: { _ in false }, keychainPassword: { _ in nil },
                                          environmentVariable: { _ in nil }, send: { _ in HTTPResponse(statusCode: 503) },
                                          now: { Date(timeIntervalSince1970: 1_800_000_000) }, sleep: { try await Task.sleep(for: $0) })
        let model = UsageModel(environment: environment, preferences: Preferences(defaults: defaults))
        #expect(model.clockInterval == .seconds(60))
        model.setSurfaceVisible("islands", true)
        #expect(model.clockInterval == .seconds(1))
        model.setSurfaceVisible("settings", true)
        model.setSurfaceVisible("islands", false)
        #expect(model.clockInterval == .seconds(1))
        model.setSurfaceVisible("settings", false)
        #expect(model.clockInterval == .seconds(60))
        #expect(model.environment.now() == model.now)
    }

    @Test("system notifications are opt-in and survive a relaunch")
    func notificationPreference() throws {
        let name = "HeadroomNotificationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        #expect(!preferences.systemNotifications)
        preferences.systemNotifications = true
        #expect(Preferences(defaults: defaults).systemNotifications)
        preferences.systemNotifications = false
        #expect(!Preferences(defaults: defaults).systemNotifications)
    }
}
