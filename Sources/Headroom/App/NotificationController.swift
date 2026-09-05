import AppKit
import HeadroomCore
import Observation
import UserNotifications

/// Optional system delivery for the same alerts that drive the island banners.
@MainActor
@Observable
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    private let preferences: Preferences
    private let center: UNUserNotificationCenter
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var permissionRequestInFlight = false
    private(set) var errorMessage: String?
    var onOpenProvider: ((ProviderID) -> Void)?
    var onSnooze: ((ProviderID, String, String) -> Void)?

    static let category = "HEADROOM_QUOTA"
    static let openOnlyCategory = "HEADROOM_QUOTA_WITHOUT_RESET"
    static let openAction = "OPEN_PROVIDER"
    static let snoozeAction = "SNOOZE_PROVIDER"

    init(preferences: Preferences, center: UNUserNotificationCenter = .current()) {
        self.preferences = preferences
        self.center = center
        super.init()
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Self.openAction, title: "Open Provider", options: .foreground),
            UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze Until Reset", options: []),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: actions, intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.openOnlyCategory, actions: [actions[0]], intentIdentifiers: [], options: []),
        ])
        Task { await refreshAuthorization() }
    }

    var enabled: Bool { preferences.systemNotifications }
    var statusText: String {
        if let errorMessage { return errorMessage }
        switch authorization {
        case .denied: return "Disabled in macOS notification settings. Island banners still work."
        case .notDetermined: return "Enable to ask macOS for notification permission."
        case .authorized, .provisional, .ephemeral: return "Quota alerts can appear in Notification Center, including when the island is hidden."
        @unknown default: return "Manage notification delivery in macOS Settings."
        }
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func setEnabled(_ enabled: Bool) async {
        guard !permissionRequestInFlight else { return }
        errorMessage = nil
        if enabled {
            permissionRequestInFlight = true
            defer { permissionRequestInFlight = false }
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                preferences.systemNotifications = allowed
            } catch {
                preferences.systemNotifications = false
                errorMessage = "Couldn't request notifications. Island banners still work."
            }
            await refreshAuthorization()
        } else {
            preferences.systemNotifications = false
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }
    }

    func deliver(_ alert: UsageAlert) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.kind == .quotaReturned ? "Quota available again" : "\(alert.provider.displayName) quota warning"
        content.body = alert.message
        content.categoryIdentifier = alert.resetsAt == nil ? Self.openOnlyCategory : Self.category
        content.threadIdentifier = alert.provider.rawValue
        content.sound = .default
        content.userInfo = ["provider": alert.provider.rawValue, "window": alert.windowID,
                            "reset": Self.resetKey(alert.resetsAt)]
        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        Task {
            guard enabled else { return }
            do {
                try await center.add(request)
                if !enabled {
                    center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                    center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
                }
            }
            catch { errorMessage = "Couldn't deliver a notification. Island banners still work." }
        }
    }

    static func resetKey(_ date: Date?) -> String { date.map { String(Int($0.timeIntervalSince1970)) } ?? "none" }

    func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { enabled ? [.banner, .list, .sound] : [] }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["provider"] as? String, let provider = ProviderID(rawValue: raw) else { return }
        let action = response.actionIdentifier
        let window = info["window"] as? String
        let reset = info["reset"] as? String
        await MainActor.run {
            if action == Self.snoozeAction, let window, let reset { onSnooze?(provider, window, reset) }
            else if action == Self.openAction || action == UNNotificationDefaultActionIdentifier { onOpenProvider?(provider) }
        }
    }
}
