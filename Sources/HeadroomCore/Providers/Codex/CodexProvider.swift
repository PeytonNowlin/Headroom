import Foundation

/// ChatGPT/Codex subscription limits via the login the Codex CLI already holds.
public struct CodexProvider: ProviderRuntime {
    public let id: ProviderID = .codex
    let environment: HostEnvironment

    public init(environment: HostEnvironment) {
        self.environment = environment
    }

    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    static let creditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!

    public func hasLocalCredentials() -> Bool {
        CodexCredentialStore(environment: environment).credential() != nil
    }

    public func refresh() async throws -> Snapshot {
        let now = environment.now()
        guard let credential = CodexCredentialStore(environment: environment).credential() else {
            return .absent(.codex, at: now)
        }
        if let expires = credential.expiresAt, expires <= now {
            return .expired(.codex, at: now)
        }

        var headers = [
            "Authorization": "Bearer \(credential.accessToken)",
            "Accept": "application/json",
            "User-Agent": "Headroom/\(HeadroomCore.version)",
        ]
        if let account = credential.accountID { headers["ChatGPT-Account-Id"] = account }

        let response: HTTPResponse
        do {
            response = try await environment.send(HTTPRequest(url: Self.usageURL, headers: headers))
        } catch {
            throw ProviderError.transient(statusCode: nil)
        }

        switch response.statusCode {
        case 200..<300:
            let json = try JSON.parse(response.body)
            var snapshot = CodexUsageMapper.snapshot(from: json, at: now)
            // Best effort: the dedicated endpoint knows each credit's expiry; the body only has a count.
            if let credits = try? await environment.send(HTTPRequest(url: Self.creditsURL, headers: headers)),
               credits.isSuccess,
               let json = try? JSON.parse(credits.body),
               let count = json["available_count"].int {
                snapshot.resetCredits = count
            }
            return snapshot
        case 401, 403:
            return .expired(.codex, at: now)
        default:
            throw ProviderError.transient(statusCode: response.statusCode)
        }
    }
}

struct CodexCredential: Sendable, Equatable {
    var accessToken: String
    var accountID: String?
    var expiresAt: Date?
}

struct CodexCredentialStore: Sendable {
    let environment: HostEnvironment

    var authFile: URL {
        if let home = environment.environmentVariable("CODEX_HOME"), !home.isEmpty {
            return environment.path(home).appending(path: "auth.json")
        }
        return environment.home.appending(path: ".codex/auth.json")
    }

    func credential() -> CodexCredential? {
        guard environment.fileExists(authFile),
              let data = try? environment.readFile(authFile),
              let json = try? JSON.parse(data) else { return nil }
        let tokens = json["tokens"]
        guard let token = tokens["access_token"].string, !token.isEmpty else { return nil }
        return CodexCredential(
            accessToken: token,
            accountID: tokens["account_id"].string,
            expiresAt: JWT.expiry(of: token)
        )
    }
}

enum CodexUsageMapper {
    static func snapshot(from json: JSON, at now: Date) -> Snapshot {
        var windows: [QuotaWindow] = []
        windows += mapWindows(json["rate_limit"], idPrefix: "", titlePrefix: "", now: now)

        for entry in json["additional_rate_limits"].array ?? [] {
            let rawName = entry["limit_name"].string ?? entry["name"].string ?? entry["model"].string ?? ""
            guard rawName.lowercased().contains("spark") else { continue }
            let limit = entry["rate_limit"].isNull ? entry : entry["rate_limit"]
            windows += mapWindows(limit, idPrefix: "spark:", titlePrefix: "Spark", now: now)
        }

        let credits = json["credits"]
        var extra: ExtraUsage?
        if !credits.isNull {
            let has = credits["has_credits"].bool ?? false
            if credits["unlimited"].bool == true {
                extra = ExtraUsage(isEnabled: true, label: "Unlimited")
            } else if let balance = credits["balance"].double {
                extra = ExtraUsage(isEnabled: has, label: "\(Formatting.dollars(balance)) credits")
            } else {
                extra = ExtraUsage(isEnabled: has, label: has ? "Available" : "None")
            }
        }

        return Snapshot(
            provider: .codex,
            fetchedAt: now,
            status: .connected,
            planName: json["plan_type"].string.map(humanizePlan),
            windows: windows,
            extraUsage: extra,
            resetCredits: json["rate_limit_reset_credits"]["available_count"].int
        )
    }

    /// Classify by window length rather than slot: Codex moves the weekly window into the
    /// primary slot when the session limit is temporarily absent.
    private static func mapWindows(_ limit: JSON, idPrefix: String, titlePrefix: String, now: Date) -> [QuotaWindow] {
        var out: [QuotaWindow] = []
        for (slot, node) in [("primary", limit["primary_window"]), ("secondary", limit["secondary_window"])] {
            guard !node.isNull, let used = node["used_percent"].double else { continue }
            let seconds = node["limit_window_seconds"].double
            let kind: (id: String, title: String, duration: TimeInterval?)
            switch seconds {
            case let s? where s <= 6 * 3600:
                kind = ("session", "Session", s)
            case let s? where s <= 8 * 86400:
                kind = ("weekly", "Weekly", s)
            case let s?:
                kind = ("window:\(Int(s))", "\(Int(s / 86400))-day", s)
            case nil:
                kind = slot == "primary" ? ("session", "Session", QuotaWindow.sessionDuration)
                                         : ("weekly", "Weekly", QuotaWindow.weeklyDuration)
            }
            let resets = node["reset_at"].epochDate
                ?? node["reset_after_seconds"].double.map { now.addingTimeInterval($0) }
            let title = titlePrefix.isEmpty ? kind.title
                : (kind.id == "session" ? titlePrefix : "\(titlePrefix) \(kind.title)")
            out.append(QuotaWindow(id: idPrefix + kind.id, title: title, usedPercent: used,
                                   resetsAt: resets, duration: kind.duration))
        }
        return out
    }

    static func humanizePlan(_ raw: String) -> String {
        let known: [String: String] = [
            "free": "Free", "plus": "Plus", "pro": "Pro", "team": "Team",
            "business": "Business", "enterprise": "Enterprise", "edu": "Edu",
        ]
        if let k = known[raw.lowercased()] { return k }
        let stripped = raw.replacingOccurrences(of: "self_serve_", with: "")
        return stripped.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

/// Reads the `exp` claim from a JWT without verifying it; we only use it to skip tokens the
/// issuer would reject anyway.
enum JWT {
    static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSON.parse(data),
              let exp = json["exp"].double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
