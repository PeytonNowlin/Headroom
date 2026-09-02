import Foundation

/// Claude subscription limits via the OAuth login Claude Code already holds.
public struct ClaudeProvider: ProviderRuntime {
    public let id: ProviderID = .claude
    let environment: HostEnvironment

    public init(environment: HostEnvironment) {
        self.environment = environment
    }

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public func hasLocalCredentials() -> Bool {
        !ClaudeCredentialStore(environment: environment).candidates().isEmpty
    }

    public func refresh() async throws -> Snapshot {
        let now = environment.now()
        let candidates = ClaudeCredentialStore(environment: environment).candidates()
        guard !candidates.isEmpty else { return .absent(.claude, at: now) }

        // Skip credentials that declare themselves expired; we never refresh tokens.
        let usable = candidates.filter { $0.expiresAt.map { $0 > now } ?? true }
        guard let credential = usable.first else {
            return .expired(.claude, at: now, planName: candidates.first?.planName)
        }

        let request = HTTPRequest(
            url: Self.usageURL,
            headers: [
                "Authorization": "Bearer \(credential.accessToken)",
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json",
                "User-Agent": "Headroom/\(HeadroomCore.version)",
            ]
        )
        let response: HTTPResponse
        do {
            response = try await environment.send(request)
        } catch {
            throw ProviderError.transient(statusCode: nil)
        }

        switch response.statusCode {
        case 200..<300:
            let json = try JSON.parse(response.body)
            return ClaudeUsageMapper.snapshot(from: json, planName: credential.planName, at: now)
        case 401, 403:
            return .expired(.claude, at: now, planName: credential.planName)
        default:
            throw ProviderError.fromResponse(response)
        }
    }
}

struct ClaudeCredential: Sendable, Equatable {
    enum Source: Sendable, Equatable { case keychain, file, environment }
    var source: Source
    var accessToken: String
    var expiresAt: Date?
    var planName: String?
}

/// Discovery order: Claude Code keychain item → credentials file → environment variable.
struct ClaudeCredentialStore: Sendable {
    let environment: HostEnvironment

    static let keychainService = "Claude Code-credentials"
    static let tokenEnvVar = "CLAUDE_CODE_OAUTH_TOKEN"

    var credentialsFile: URL {
        if let dir = environment.environmentVariable("CLAUDE_CONFIG_DIR"), !dir.isEmpty {
            return environment.path(dir).appending(path: ".credentials.json")
        }
        return environment.home.appending(path: ".claude/.credentials.json")
    }

    func candidates() -> [ClaudeCredential] {
        var out: [ClaudeCredential] = []
        if let data = environment.keychainPassword(Self.keychainService),
           let cred = Self.parse(data, source: .keychain) {
            out.append(cred)
        }
        if environment.fileExists(credentialsFile),
           let data = try? environment.readFile(credentialsFile),
           let cred = Self.parse(data, source: .file) {
            out.append(cred)
        }
        if let token = environment.environmentVariable(Self.tokenEnvVar)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            out.append(ClaudeCredential(source: .environment, accessToken: token, expiresAt: nil, planName: nil))
        }
        return out
    }

    static func parse(_ data: Data, source: ClaudeCredential.Source) -> ClaudeCredential? {
        guard let json = try? JSON.parse(data) else { return nil }
        let oauth = json["claudeAiOauth"]
        guard let token = oauth["accessToken"].string, !token.isEmpty else { return nil }
        let plan = oauth["subscriptionType"].string.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return ClaudeCredential(
            source: source,
            accessToken: token,
            expiresAt: oauth["expiresAt"].epochDate,
            planName: plan
        )
    }
}

enum ClaudeUsageMapper {
    static func snapshot(from json: JSON, planName: String?, at now: Date) -> Snapshot {
        var windows: [QuotaWindow] = []

        if let limits = json["limits"].array, !limits.isEmpty {
            for limit in limits {
                guard let kind = limit["kind"].string, let percent = limit["percent"].double else { continue }
                let resets = limit["resets_at"].isoDate
                switch kind {
                case "session":
                    windows.append(QuotaWindow(id: "session", title: "Session", usedPercent: percent,
                                               resetsAt: resets, duration: QuotaWindow.sessionDuration,
                                               isStarted: resets != nil))
                case "weekly_all":
                    windows.append(QuotaWindow(id: "weekly", title: "Weekly", usedPercent: percent,
                                               resetsAt: resets, duration: QuotaWindow.weeklyDuration))
                case "weekly_scoped":
                    let name = limit["scope"]["model"]["display_name"].string
                        ?? limit["scope"]["model"]["id"].string
                        ?? "Model"
                    windows.append(QuotaWindow(id: "weekly:\(name)", title: name, usedPercent: percent,
                                               resetsAt: resets, duration: QuotaWindow.weeklyDuration))
                default:
                    continue
                }
            }
        } else {
            // Older payload shape: named window objects with `utilization`.
            let named: [(String, String, String, TimeInterval)] = [
                ("five_hour", "session", "Session", QuotaWindow.sessionDuration),
                ("seven_day", "weekly", "Weekly", QuotaWindow.weeklyDuration),
                ("seven_day_opus", "weekly:Opus", "Opus", QuotaWindow.weeklyDuration),
                ("seven_day_sonnet", "weekly:Sonnet", "Sonnet", QuotaWindow.weeklyDuration),
            ]
            for (key, id, title, duration) in named {
                let node = json[key]
                guard let used = node["utilization"].double else { continue }
                let resets = node["resets_at"].isoDate
                windows.append(QuotaWindow(id: id, title: title, usedPercent: used, resetsAt: resets,
                                           duration: duration, isStarted: id != "session" || resets != nil))
            }
        }

        let extra = json["extra_usage"]
        var extraUsage: ExtraUsage?
        if !extra.isNull {
            let enabled = extra["is_enabled"].bool ?? false
            let places = extra["decimal_places"].int ?? 2
            let scale = pow(10.0, Double(places))
            let used = extra["used_credits"].double.map { $0 / scale }
            let limit = extra["monthly_limit"].double.map { $0 / scale }
            extraUsage = ExtraUsage(isEnabled: enabled, usedDollars: used, limitDollars: limit)
        }

        return Snapshot(
            provider: .claude,
            fetchedAt: now,
            status: .connected,
            planName: planName,
            windows: windows,
            extraUsage: extraUsage
        )
    }
}
