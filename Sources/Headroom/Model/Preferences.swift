import Foundation
import HeadroomCore
import Observation
import ServiceManagement

/// How much a provider matters. One control, three answers — it replaces both the old
/// visibility picker and any per-provider alert switches.
enum ProviderTier: String, Codable, CaseIterable {
    /// A main coding agent. Running low here stops your work, so it summons the island.
    case main
    /// A side provider — research, one-offs. Shown alongside, never the reason to appear.
    case secondary
    case hidden

    var title: String {
        switch self {
        case .main: "Main"
        case .secondary: "Side"
        case .hidden: "Hidden"
        }
    }

    /// Claude and Codex are main agents until told otherwise; everything else rides along.
    static func `default`(for id: ProviderID) -> ProviderTier {
        switch id {
        case .claude, .codex: .main
        case .grok, .cursor, .opencode: .secondary
        }
    }
}

/// Only kept so preferences written before tiers existed still decode; `hide` carries over.
enum LegacyVisibility: String, Codable {
    case auto, show, hide
}

/// User preferences, persisted to UserDefaults as one JSON blob. Every write applies immediately.
@MainActor
@Observable
final class Preferences {
    private struct Stored: Codable {
        var alerts: [ProviderID: AlertOptions]?
        var systemNotifications: Bool?
        var tiers: [ProviderID: ProviderTier]?
        var visibility: [ProviderID: LegacyVisibility] = [:]
        var order: [ProviderID] = ProviderID.allCases
        var hideInFullScreen = false
        var showMenuBarIcon = false
        var didRegisterLoginItem = false
        var didCompleteFirstRun = false
    }

    private let defaults: UserDefaults
    private static let key = "headroom.preferences"
    private var stored: Stored {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        } else {
            stored = Stored()
        }
        // Any provider added after the order was saved goes to the end.
        for id in ProviderID.allCases where !stored.order.contains(id) { stored.order.append(id) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
    }

    // MARK: - Providers

    var order: [ProviderID] {
        get { stored.order }
        set { stored.order = newValue }
    }

    /// A provider's tier, falling back to the default — or to `hidden` when an older install
    /// had hidden it.
    func tier(_ id: ProviderID) -> ProviderTier {
        if let tier = stored.tiers?[id] { return tier }
        if stored.visibility[id] == .hide { return .hidden }
        return .default(for: id)
    }

    func setTier(_ tier: ProviderTier, for id: ProviderID) {
        var tiers = stored.tiers ?? [:]
        tiers[id] = tier
        stored.tiers = tiers
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = stored.order
        order.move(fromOffsets: source, toOffset: destination)
        stored.order = order
    }

    func alertOptions(_ id: ProviderID) -> AlertOptions { stored.alerts?[id] ?? AlertOptions() }

    func setAlertOptions(_ options: AlertOptions, for id: ProviderID) {
        var alerts = stored.alerts ?? [:]
        alerts[id] = options
        stored.alerts = alerts
    }

    var systemNotifications: Bool {
        get { stored.systemNotifications ?? false }
        set { stored.systemNotifications = newValue }
    }

    // MARK: - Behavior

    var hideInFullScreen: Bool {
        get { stored.hideInFullScreen }
        set { stored.hideInFullScreen = newValue }
    }

    var showMenuBarIcon: Bool {
        get { stored.showMenuBarIcon }
        set { stored.showMenuBarIcon = newValue }
    }

    var didCompleteFirstRun: Bool {
        get { stored.didCompleteFirstRun }
        set { stored.didCompleteFirstRun = newValue }
    }

    // MARK: - Launch at login (SMAppService is the source of truth)

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                HeadroomLog.polling.error("launch at login change failed: \(String(describing: error), privacy: .public)")
            }
            launchAtLoginRevision += 1
        }
    }

    /// Bumped after every register/unregister so observers re-read the SMAppService status.
    private(set) var launchAtLoginRevision = 0

    /// First launch registers as a login item once; afterwards the user's choice stands.
    func registerLoginItemOnFirstRun() {
        guard !stored.didRegisterLoginItem else { return }
        stored.didRegisterLoginItem = true
        launchAtLogin = true
    }
}
