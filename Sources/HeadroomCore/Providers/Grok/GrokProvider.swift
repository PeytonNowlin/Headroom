import Foundation

/// Grok Build usage via the login the Grok CLI already holds.
public struct GrokProvider: ProviderRuntime {
    public let id: ProviderID = .grok
    let environment: HostEnvironment

    public init(environment: HostEnvironment) {
        self.environment = environment
    }

    static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    static let settingsURL = URL(string: "https://cli-chat-proxy.grok.com/v1/settings")!
    static let weeklyPeriodType = "USAGE_PERIOD_TYPE_WEEKLY"
    static let teamNote = "Business team account — Grok publishes no personal quota; spend is tracked locally."

    public func hasLocalCredentials() -> Bool {
        GrokCredentialStore(environment: environment).credential() != nil
    }

    public func refresh() async throws -> Snapshot {
        let now = environment.now()
        guard let credential = GrokCredentialStore(environment: environment).credential() else {
            return .absent(.grok, at: now)
        }
        if let expires = credential.expiresAt, expires <= now {
            return .expired(.grok, at: now)
        }

        let headers = [
            "Authorization": "Bearer \(credential.key)",
            "X-XAI-Token-Auth": "xai-grok-cli",
            "Accept": "application/json",
            "User-Agent": "Headroom/\(HeadroomCore.version)",
        ]

        // Plan name is best effort and never blocks the quota fetch.
        var planName: String?
        if let settings = try? await environment.send(HTTPRequest(url: Self.settingsURL, headers: headers)),
           settings.isSuccess, let json = try? JSON.parse(settings.body) {
            planName = json["subscription_tier_display"].string?.trimmingCharacters(in: .whitespaces)
            if planName?.isEmpty == true { planName = nil }
        }

        let response: HTTPResponse
        do {
            response = try await environment.send(HTTPRequest(url: Self.billingURL, headers: headers))
        } catch {
            throw ProviderError.transient(statusCode: nil)
        }

        switch response.statusCode {
        case 200..<300:
            let json = try JSON.parse(response.body)
            return GrokUsageMapper.snapshot(from: json, planName: planName, at: now)
        case 401, 403:
            return .expired(.grok, at: now, planName: planName)
        case 412 where Self.isNoPersonalTeam(response.body):
            // A team principal has no personal billing pool and Grok offers no team-scoped
            // endpoint (openusage#1162). This is an account shape, not a failure.
            var snapshot = Snapshot(provider: .grok, fetchedAt: now, status: .connected, planName: planName)
            snapshot.note = Self.teamNote
            return snapshot
        default:
            throw ProviderError.transient(statusCode: response.statusCode)
        }
    }

    private static func isNoPersonalTeam(_ body: Data) -> Bool {
        guard let json = try? JSON.parse(body) else { return false }
        return json["error"].string?.lowercased().contains("no personal team") == true
    }
}

struct GrokCredential: Sendable, Equatable {
    var key: String
    var expiresAt: Date?
    var isTeam: Bool
}

/// `~/.grok/auth.json` is a dictionary keyed by issuer and client id; the bearer token is `key`.
struct GrokCredentialStore: Sendable {
    let environment: HostEnvironment

    var authFile: URL {
        if let home = environment.environmentVariable("GROK_HOME"), !home.isEmpty {
            return environment.path(home).appending(path: "auth.json")
        }
        return environment.home.appending(path: ".grok/auth.json")
    }

    func credential() -> GrokCredential? {
        guard environment.fileExists(authFile),
              let data = try? environment.readFile(authFile),
              let entries = (try? JSON.parse(data))?.object else { return nil }
        for key in entries.keys.sorted() {
            let entry = entries[key]!
            guard let token = entry["key"].string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !token.isEmpty else { continue }
            let expires = entry["expires_at"].isoDate ?? entry["expires_at"].epochDate
                ?? entry["expires"].isoDate ?? entry["expires"].epochDate
            return GrokCredential(
                key: token,
                expiresAt: expires,
                isTeam: entry["principal_type"].string?.lowercased() == "team"
            )
        }
        return nil
    }
}

/// Decodes the proto-JSON credits config: zero-valued fields are omitted, so an absent
/// `creditUsagePercent` is 0 and an absent `onDemandCap` is disabled.
enum GrokUsageMapper {
    static func snapshot(from json: JSON, planName: String?, at now: Date) -> Snapshot {
        let config = json["config"]
        var windows: [QuotaWindow] = []

        let period = config["currentPeriod"]
        if period["type"].string == GrokProvider.weeklyPeriodType,
           let start = period["start"].isoDate, let end = period["end"].isoDate, end > start {
            let used = config["creditUsagePercent"].double ?? 0
            windows.append(QuotaWindow(id: "weekly", title: "Weekly", usedPercent: max(0, min(100, used)),
                                       resetsAt: end, duration: end.timeIntervalSince(start)))
        }

        let cap = config["onDemandCap"]["val"].double ?? 0
        let extra = cap > 0
            ? ExtraUsage(isEnabled: true, label: "\(cap.rounded() == cap ? String(Int(cap)) : String(cap)) cap")
            : ExtraUsage(isEnabled: false, label: "Disabled")

        return Snapshot(provider: .grok, fetchedAt: now, status: .connected, planName: planName,
                        windows: windows, extraUsage: extra)
    }
}
