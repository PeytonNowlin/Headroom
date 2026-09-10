import Foundation

/// OpenCode Go plan windows, read with the API key the OpenCode CLI already holds. Zen
/// pay-as-you-go has no quota of its own; those accounts get spend tiles and a note instead.
public struct OpenCodeProvider: ProviderRuntime {
    public let id: ProviderID = .opencode
    let environment: HostEnvironment

    public init(environment: HostEnvironment) {
        self.environment = environment
    }

    static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!
    static let zenOnlyNote = "No OpenCode Go subscription on this key — Zen usage is tracked as local spend."

    public func hasLocalCredentials() -> Bool {
        OpenCodeCredentialStore(environment: environment).goAPIKey() != nil
    }

    public func refresh() async throws -> Snapshot {
        let now = environment.now()
        guard let key = OpenCodeCredentialStore(environment: environment).goAPIKey() else {
            return .absent(.opencode, at: now)
        }

        let request = HTTPRequest(url: Self.usageURL, headers: [
            "Authorization": "Bearer \(key)",
            "Accept": "application/json",
            "User-Agent": "Headroom/\(HeadroomCore.version)",
        ])
        let response: HTTPResponse
        do {
            response = try await environment.send(request)
        } catch {
            throw ProviderError.transient(statusCode: nil)
        }

        switch response.statusCode {
        case 200..<300:
            let json = try JSON.parse(response.body)
            return try OpenCodeUsageMapper.snapshot(from: json, at: now)
        case 401:
            return .expired(.opencode, at: now)
        case 403 where Self.errorType(response.body) == "EntitlementError":
            // A valid key on a Zen-only account. That is an account shape, not a failure: the
            // spend tiles still work, so stay connected and explain the missing rings.
            var snapshot = Snapshot(provider: .opencode, fetchedAt: now, status: .connected)
            snapshot.note = Self.zenOnlyNote
            return snapshot
        default:
            throw ProviderError.fromResponse(response)
        }
    }

    /// The upstream error discriminator (`AuthError`, `EntitlementError`, …) when the body is the
    /// documented `{ error: { type, message } }` shape; nil for HTML or empty bodies.
    private static func errorType(_ body: Data) -> String? {
        guard let json = try? JSON.parse(body) else { return nil }
        let type = json["error"]["type"].string?.trimmingCharacters(in: .whitespaces)
        return (type?.isEmpty == false) ? type : nil
    }
}

/// `~/.local/share/opencode/auth.json` keys credentials by provider; OpenCode Go's API key lives
/// under `opencode-go`. Sibling entries (Zen, BYO keys, OAuth logins) are left alone.
struct OpenCodeCredentialStore: Sendable {
    let environment: HostEnvironment

    var authFile: URL { OpenCodePaths.authFile(environment) }

    func goAPIKey() -> String? {
        guard environment.fileExists(authFile),
              let data = try? environment.readFile(authFile),
              let json = try? JSON.parse(data) else { return nil }
        let key = json["opencode-go"]["key"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == false) ? key : nil
    }
}

/// `GET /zen/go/v1/usage` reports percent used per window (the same numbers as the OpenCode
/// dashboard, account-wide) with an ISO reset time — not dollars.
enum OpenCodeUsageMapper {
    static let monthlyDuration: TimeInterval = 30 * 24 * 3600

    static func snapshot(from json: JSON, at now: Date) throws -> Snapshot {
        let usage = json["usage"]
        let windows = [
            window(usage["rolling"], id: "session", title: "Session", duration: QuotaWindow.sessionDuration),
            window(usage["weekly"], id: "weekly", title: "Weekly", duration: QuotaWindow.weeklyDuration),
            window(usage["monthly"], id: "monthly", title: "Monthly", duration: monthlyDuration),
        ].compactMap { $0 }
        guard !windows.isEmpty else {
            throw ProviderError.malformedResponse("no usage windows in /zen/go/v1/usage")
        }
        return Snapshot(provider: .opencode, fetchedAt: now, status: .connected,
                        planName: "Go", windows: windows)
    }

    /// A window with no reset time has not begun; the ring shows it as not started rather than
    /// pretending a countdown exists.
    private static func window(_ json: JSON, id: String, title: String, duration: TimeInterval) -> QuotaWindow? {
        guard let percent = json["percent"].double else { return nil }
        let resets = json["resetsAt"].isoDate ?? json["resetsAt"].epochDate
        return QuotaWindow(id: id, title: title, usedPercent: max(0, min(100, percent)),
                           resetsAt: resets, duration: duration, isStarted: resets != nil)
    }
}
