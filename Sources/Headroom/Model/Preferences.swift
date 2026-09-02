import Foundation
import HeadroomCore
import Observation
import ServiceManagement

enum ProviderVisibility: String, Codable, CaseIterable {
    /// Shown when local credentials exist.
    case auto
    case show
    case hide

    var title: String {
        switch self {
        case .auto: "Automatic"
        case .show: "Always show"
        case .hide: "Hide"
        }
    }
}

/// User preferences, persisted to UserDefaults as one JSON blob. Every write applies immediately.
@MainActor
@Observable
final class Preferences {
    private struct Stored: Codable {
        var visibility: [ProviderID: ProviderVisibility] = [:]
        var order: [ProviderID] = ProviderID.allCases
        var hideInFullScreen = true
        var showMenuBarIcon = false
        var didRegisterLoginItem = false
        var didCompleteFirstRun = false
    }

    private static let key = "headroom.preferences"
    private var stored: Stored {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
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
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: - Providers

    var order: [ProviderID] {
        get { stored.order }
        set { stored.order = newValue }
    }

    func visibility(_ id: ProviderID) -> ProviderVisibility { stored.visibility[id] ?? .auto }

    func setVisibility(_ v: ProviderVisibility, for id: ProviderID) {
        stored.visibility[id] = v
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = stored.order
        order.move(fromOffsets: source, toOffset: destination)
        stored.order = order
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
