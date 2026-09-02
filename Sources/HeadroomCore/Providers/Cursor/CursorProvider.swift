import Foundation

/// Cursor plan usage via the session the Cursor app (or `agent login`) already holds.
///
/// Read-only by policy: the access token is read from Cursor's state database or keychain item
/// and never refreshed or written back. When it lapses, the provider reads `expired` until the
/// Cursor app rotates it.
public struct CursorProvider: ProviderRuntime {
    public let id: ProviderID = .cursor
    let environment: HostEnvironment

    public init(environment: HostEnvironment) {
        self.environment = environment
    }

    static let usageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    static let planURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo")!
    static let grokBotURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!
    static let requestUsageURL = URL(string: "https://cursor.com/api/usage")!
    static let noSubscriptionNote = "No active Cursor subscription — nothing to meter."
    static let noMeterNote = "Cursor reports no included-usage meter for this plan."

    public func hasLocalCredentials() -> Bool {
        CursorCredentialStore(environment: environment).accessToken() != nil
    }

    public func refresh() async throws -> Snapshot {
        let now = environment.now()
        guard let token = CursorCredentialStore(environment: environment).accessToken() else {
            return .absent(.cursor, at: now)
        }
        if let expires = JWT.expiry(of: token), expires <= now {
            return .expired(.cursor, at: now)
        }

        let response: HTTPResponse
        do {
            response = try await environment.send(Self.connectRequest(Self.usageURL, token: token))
        } catch {
            throw ProviderError.transient(statusCode: nil)
        }

        switch response.statusCode {
        case 200..<300:
            break
        case 401, 403:
            return .expired(.cursor, at: now)
        default:
            throw ProviderError.fromResponse(response)
        }
        let usage = try JSON.parse(response.body)

        // Everything past the primary usage call is best effort and never fails the refresh.
        let planName = await optionalJSON(Self.connectRequest(Self.planURL, token: token))
            .flatMap { CursorUsageMapper.planName(from: $0) }
        let grokBot = await optionalJSON(Self.connectRequest(Self.grokBotURL, token: token))

        var snapshot = CursorUsageMapper.snapshot(from: usage, planName: planName, at: now)
        if snapshot.windows.isEmpty, snapshot.note == Self.noMeterNote,
           let session = CursorSession(accessToken: token),
           let requests = await optionalJSON(Self.restRequest(Self.requestUsageURL, query: ["user": session.userID], session: session)),
           let window = CursorUsageMapper.requestWindow(from: requests) {
            snapshot.windows = [window]
            snapshot.note = nil
        }
        if let grokBot, let window = CursorUsageMapper.grokBotWindow(from: grokBot) {
            snapshot.windows.append(window)
        }
        return snapshot
    }

    private func optionalJSON(_ request: HTTPRequest) async -> JSON? {
        guard let response = try? await environment.send(request), response.isSuccess else { return nil }
        return try? JSON.parse(response.body)
    }

    static func connectRequest(_ url: URL, token: String) -> HTTPRequest {
        HTTPRequest(url: url, method: "POST", headers: [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "User-Agent": "Headroom/\(HeadroomCore.version)",
        ], body: Data("{}".utf8))
    }

    static func restRequest(_ url: URL, query: [String: String], session: CursorSession) -> HTTPRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return HTTPRequest(url: components.url!, headers: [
            "Cookie": "WorkosCursorSessionToken=\(session.cookieToken)",
            "User-Agent": "Headroom/\(HeadroomCore.version)",
        ])
    }
}

/// The dashboard's cookie session, derived from the access token's subject (`auth0|user_…`).
struct CursorSession: Sendable, Equatable {
    var userID: String
    var cookieToken: String

    init?(accessToken: String) {
        guard let subject = JWT.claims(of: accessToken)?["sub"].string else { return nil }
        let parts = subject.split(separator: "|", omittingEmptySubsequences: false)
        let user = String(parts.count > 1 ? parts[1] : parts[0]).trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty else { return nil }
        userID = user
        cookieToken = "\(user)%3A%3A\(accessToken)"
    }
}

/// Cursor's state database first (what the app writes), then the keychain item `agent login` uses.
struct CursorCredentialStore: Sendable {
    static let accessTokenKey = "cursorAuth/accessToken"
    static let keychainService = "cursor-access-token"
    let environment: HostEnvironment

    var stateDatabase: URL {
        environment.home.appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    func accessToken() -> String? {
        if let token = environment.stateDatabaseValue(stateDatabase, Self.accessTokenKey), !token.isEmpty {
            return token
        }
        if let data = environment.keychainPassword(Self.keychainService),
           let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }
        return nil
    }
}

enum CursorUsageMapper {
    static let monthly: TimeInterval = 30 * 86400

    static func planName(from json: JSON) -> String? {
        let raw = json["planInfo"]["planName"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return raw.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    /// `GetCurrentPeriodUsage`: `planUsage` carries the included allowance (percent, or cents
    /// against a limit for teams), and `spendLimitUsage` the on-demand pool.
    static func snapshot(from json: JSON, planName: String?, at now: Date) -> Snapshot {
        var snapshot = Snapshot(provider: .cursor, fetchedAt: now, status: .connected, planName: planName)
        guard json["enabled"].bool != false, let plan = json["planUsage"].object else {
            snapshot.note = CursorProvider.noSubscriptionNote
            return snapshot
        }
        let planJSON = JSON.object(plan)

        let (resetsAt, duration) = billingCycle(json)
        let limit = planJSON["limit"].double
        let spent = planJSON["totalSpend"].double ?? ((limit ?? 0) - (planJSON["remaining"].double ?? 0))
        let computed: Double? = limit.flatMap { $0 > 0 ? spent / $0 * 100 : nil }

        if let percent = planJSON["totalPercentUsed"].double ?? computed {
            snapshot.windows.append(QuotaWindow(id: "included", title: "Included usage",
                                                usedPercent: clamp(percent), resetsAt: resetsAt, duration: duration))
        } else {
            snapshot.note = CursorProvider.noMeterNote
        }
        if let auto = planJSON["autoPercentUsed"].double {
            snapshot.windows.append(QuotaWindow(id: "auto", title: "Cursor models",
                                                usedPercent: clamp(auto), resetsAt: resetsAt, duration: duration))
        }
        if let api = planJSON["apiPercentUsed"].double {
            snapshot.windows.append(QuotaWindow(id: "api", title: "Other models",
                                                usedPercent: clamp(api), resetsAt: resetsAt, duration: duration))
        }

        snapshot.extraUsage = extraUsage(json["spendLimitUsage"])
        return snapshot
    }

    private static func extraUsage(_ spend: JSON) -> ExtraUsage? {
        guard spend.object != nil else { return nil }
        let limit = spend["individualLimit"].double ?? spend["pooledLimit"].double ?? 0
        let remaining = spend["individualRemaining"].double ?? spend["pooledRemaining"].double ?? 0
        let reported = [spend["individualUsed"].double, spend["pooledUsed"].double, spend["totalSpend"].double].compactMap { $0 }
        let used = reported.first { $0 > 0 } ?? max(0, limit - remaining, reported.first ?? 0)
        if limit > 0 {
            return ExtraUsage(isEnabled: true, usedDollars: used / 100, limitDollars: limit / 100)
        }
        if used > 0 {
            return ExtraUsage(isEnabled: true, usedDollars: used / 100)
        }
        return ExtraUsage(isEnabled: false)
    }

    private static func billingCycle(_ json: JSON) -> (Date?, TimeInterval?) {
        let start = json["billingCycleStart"].epochDate
        let end = json["billingCycleEnd"].epochDate
        if let start, let end, end > start { return (end, end.timeIntervalSince(start)) }
        return (end, monthly)
    }

    /// Enterprise/request-based accounts: `cursor.com/api/usage` reports `gpt-4.numRequests`
    /// against `maxRequestUsage` for the month starting `startOfMonth`.
    static func requestWindow(from json: JSON) -> QuotaWindow? {
        let gpt4 = json["gpt-4"]
        guard let limit = gpt4["maxRequestUsage"].double, limit > 0 else { return nil }
        let used = gpt4["numRequests"].double ?? gpt4["numRequestsTotal"].double ?? 0
        let start = json["startOfMonth"].isoDate
        return QuotaWindow(id: "requests", title: "Requests", usedPercent: clamp(used / limit * 100),
                           resetsAt: start?.addingTimeInterval(monthly), duration: monthly)
    }

    /// Grok Bot ("Sand") has its own weekly allowance on the same account. Pooled enterprise
    /// allowances and zero-limit plans have no personal meter.
    static func grokBotWindow(from json: JSON) -> QuotaWindow? {
        guard json["usesPooledEnterpriseAllowance"].bool != true,
              json["hasNonZeroIncludedLimit"].bool != false,
              json["includedLimitZero"].bool != true,
              let percent = json["usagePercent"].double, percent >= 0 else { return nil }
        let reset = json["nextResetTimestampUtc"].isoDate
        let start = json["currentPeriodStart"].isoDate
        let duration: TimeInterval = if let start, let reset, reset > start { reset.timeIntervalSince(start) } else { QuotaWindow.weeklyDuration }
        return QuotaWindow(id: "grok-bot", title: "Grok Bot", usedPercent: clamp(percent), resetsAt: reset, duration: duration)
    }

    private static func clamp(_ percent: Double) -> Double { max(0, min(100, percent)) }
}
