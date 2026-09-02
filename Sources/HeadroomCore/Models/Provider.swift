import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case claude
    case codex
    case grok

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        }
    }

    /// The CLI command a user runs to sign in again.
    public var signInCommand: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .grok: "grok"
        }
    }
}

/// How a provider's credentials and last refresh stand.
public enum ConnectionStatus: String, Sendable, Equatable, Codable {
    /// Credentials found and the last refresh succeeded within the staleness window.
    case connected
    /// Last good snapshot is older than the staleness window.
    case stale
    /// Credentials are present but rejected (or past their own expiry).
    case expired
    /// No local credentials exist for this provider.
    case absent
}

/// A protocol every provider implements. Structured as credential store → usage client → mapper.
public protocol ProviderRuntime: Sendable {
    var id: ProviderID { get }
    /// True when any credential source has something to try, regardless of validity.
    func hasLocalCredentials() -> Bool
    /// Fetches a fresh snapshot. Throws `ProviderError.transient` for retryable failures
    /// (network, 429, 5xx); returns `.expired` / `.absent` statuses for credential problems.
    func refresh() async throws -> Snapshot
}

public enum ProviderError: Error, Sendable, Equatable {
    case transient(statusCode: Int?)
    /// HTTP 429; `retryAfter` is the server's hint in seconds when it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    case malformedResponse(String)

    /// Maps a non-success HTTP response to the right retryable error.
    public static func fromResponse(_ response: HTTPResponse) -> ProviderError {
        if response.statusCode == 429 {
            let hint = response.headers["retry-after"].flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            return .rateLimited(retryAfter: hint)
        }
        return .transient(statusCode: response.statusCode)
    }
}
