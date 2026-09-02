import Foundation

/// Every side effect Core performs goes through this value. Production wires the real
/// filesystem, keychain, network, and clock; tests wire fixtures.
public struct HostEnvironment: Sendable {
    public var home: URL
    public var timeZone: TimeZone
    public var readFile: @Sendable (URL) throws -> Data
    public var fileExists: @Sendable (URL) -> Bool
    /// Contents of a generic keychain password item for the given service, if any.
    public var keychainPassword: @Sendable (_ service: String) -> Data?
    public var environmentVariable: @Sendable (String) -> String?
    public var send: @Sendable (HTTPRequest) async throws -> HTTPResponse
    public var now: @Sendable () -> Date
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(
        home: URL,
        timeZone: TimeZone,
        readFile: @escaping @Sendable (URL) throws -> Data,
        fileExists: @escaping @Sendable (URL) -> Bool,
        keychainPassword: @escaping @Sendable (String) -> Data?,
        environmentVariable: @escaping @Sendable (String) -> String?,
        send: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse,
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.home = home
        self.timeZone = timeZone
        self.readFile = readFile
        self.fileExists = fileExists
        self.keychainPassword = keychainPassword
        self.environmentVariable = environmentVariable
        self.send = send
        self.now = now
        self.sleep = sleep
    }

    /// Expands a leading `~` against `home`.
    public func path(_ raw: String) -> URL {
        if raw.hasPrefix("~/") {
            return home.appending(path: String(raw.dropFirst(2)))
        }
        if raw == "~" { return home }
        return URL(filePath: raw)
    }
}

public struct HTTPRequest: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }
}
