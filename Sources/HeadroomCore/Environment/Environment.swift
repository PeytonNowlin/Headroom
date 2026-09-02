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
    /// Recursively lists regular files under a directory with the given extension (no dot).
    public var enumerateFiles: @Sendable (_ directory: URL, _ extension: String) -> [URL]
    public var fileInfo: @Sendable (URL) -> FileInfo?
    /// Bytes from `offset` to end of file.
    public var readFileRange: @Sendable (URL, _ offset: Int) throws -> Data
    /// Writes only inside `dataDirectory`; Core never writes anywhere else.
    public var writeFile: @Sendable (URL, Data) throws -> Void
    /// Headroom's own cache/preferences directory (Application Support/Headroom).
    public var dataDirectory: URL
    /// One value from a VS Code-style `ItemTable` state database, opened read-only.
    public var stateDatabaseValue: @Sendable (_ database: URL, _ key: String) -> String?

    public init(
        home: URL,
        timeZone: TimeZone,
        readFile: @escaping @Sendable (URL) throws -> Data,
        fileExists: @escaping @Sendable (URL) -> Bool,
        keychainPassword: @escaping @Sendable (String) -> Data?,
        environmentVariable: @escaping @Sendable (String) -> String?,
        send: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse,
        now: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        enumerateFiles: @escaping @Sendable (URL, String) -> [URL] = { _, _ in [] },
        fileInfo: @escaping @Sendable (URL) -> FileInfo? = { _ in nil },
        readFileRange: @escaping @Sendable (URL, Int) throws -> Data = { _, _ in Data() },
        writeFile: @escaping @Sendable (URL, Data) throws -> Void = { _, _ in },
        dataDirectory: URL? = nil,
        stateDatabaseValue: @escaping @Sendable (URL, String) -> String? = { _, _ in nil }
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
        self.enumerateFiles = enumerateFiles
        self.fileInfo = fileInfo
        self.readFileRange = readFileRange
        self.writeFile = writeFile
        self.dataDirectory = dataDirectory ?? home.appending(path: "Library/Application Support/Headroom")
        self.stateDatabaseValue = stateDatabaseValue
    }

    public var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
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

public struct FileInfo: Sendable, Equatable {
    public var size: Int
    public var modified: Date

    public init(size: Int, modified: Date) {
        self.size = size
        self.modified = modified
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
