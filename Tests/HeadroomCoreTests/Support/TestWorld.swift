import Foundation
import HeadroomCore
import Synchronization

/// An in-memory machine: files, keychain, env vars, canned HTTP responses, and a virtual clock
/// whose `sleep` advances time instantly and records every requested delay.
final class TestWorld: Sendable {
    struct State {
        var files: [String: Data] = [:]
        var keychain: [String: Data] = [:]
        var env: [String: String] = [:]
        var responses: [String: [HTTPResponse]] = [:]
        var fallbackResponse: HTTPResponse?
        var requests: [HTTPRequest] = []
        var now: Date
        var sleeps: [Duration] = []
    }

    let state: Mutex<State>
    let home = URL(filePath: "/Users/test")
    let timeZone = TimeZone(identifier: "America/New_York")!

    init(now: Date = Date(timeIntervalSince1970: 1_788_300_000)) {
        state = Mutex(State(now: now))
    }

    // MARK: - Setup

    func file(_ relativeToHome: String, _ contents: String) {
        file(relativeToHome, Data(contents.utf8))
    }

    func file(_ relativeToHome: String, _ data: Data) {
        let url = home.appending(path: relativeToHome)
        state.withLock { $0.files[url.path(percentEncoded: false)] = data }
    }

    func absoluteFile(_ path: String, _ contents: String) {
        state.withLock { $0.files[path] = Data(contents.utf8) }
    }

    func append(_ relativeToHome: String, _ contents: String) {
        let path = home.appending(path: relativeToHome).path(percentEncoded: false)
        state.withLock { $0.files[path, default: Data()].append(Data(contents.utf8)) }
    }

    func fileContents(_ relativeToHome: String) -> Data? {
        let path = home.appending(path: relativeToHome).path(percentEncoded: false)
        return state.withLock { $0.files[path] }
    }

    func keychain(_ service: String, _ contents: String) {
        state.withLock { $0.keychain[service] = Data(contents.utf8) }
    }

    func env(_ key: String, _ value: String) {
        state.withLock { $0.env[key] = value }
    }

    /// Queue a response for a URL; responses are consumed in order, the last one repeating.
    func respond(_ url: String, _ response: HTTPResponse) {
        state.withLock { $0.responses[url, default: []].append(response) }
    }

    func respond(_ url: String, status: Int = 200, json: String) {
        respond(url, HTTPResponse(statusCode: status, body: Data(json.utf8)))
    }

    func respond(_ url: String, status: Int = 200, fixture: String) {
        respond(url, HTTPResponse(statusCode: status, body: Fixtures.data(fixture)))
    }

    func respondToEverything(_ response: HTTPResponse) {
        state.withLock { $0.fallbackResponse = response }
    }

    // MARK: - Observation

    var requests: [HTTPRequest] { state.withLock { $0.requests } }
    var sleeps: [Duration] { state.withLock { $0.sleeps } }
    var now: Date { state.withLock { $0.now } }

    func advance(by seconds: TimeInterval) {
        state.withLock { $0.now = $0.now.addingTimeInterval(seconds) }
    }

    // MARK: - HostEnvironment

    var environment: HostEnvironment {
        // Capture the world (a Sendable class) rather than the Mutex, which is non-copyable.
        let world = self
        return HostEnvironment(
            home: home,
            timeZone: timeZone,
            readFile: { url in
                let path = url.path(percentEncoded: false)
                guard let data = world.state.withLock({ $0.files[path] }) else {
                    throw CocoaError(.fileReadNoSuchFile)
                }
                return data
            },
            fileExists: { url in
                let path = url.path(percentEncoded: false)
                return world.state.withLock { s in
                    s.files[path] != nil || s.files.keys.contains { $0.hasPrefix(path + "/") }
                }
            },
            keychainPassword: { service in world.state.withLock { $0.keychain[service] } },
            environmentVariable: { key in world.state.withLock { $0.env[key] } },
            send: { request in
                let key = request.url.absoluteString
                let response: HTTPResponse? = world.state.withLock { s in
                    s.requests.append(request)
                    if var queue = s.responses[key], !queue.isEmpty {
                        let r = queue.removeFirst()
                        if queue.isEmpty { queue = [r] }
                        s.responses[key] = queue
                        return r
                    }
                    return s.fallbackResponse
                }
                guard let response else { throw URLError(.notConnectedToInternet) }
                return response
            },
            now: { world.state.withLock { $0.now } },
            sleep: { duration in
                world.state.withLock { s in
                    s.sleeps.append(duration)
                    let seconds = Double(duration.components.seconds)
                        + Double(duration.components.attoseconds) / 1e18
                    s.now = s.now.addingTimeInterval(seconds)
                }
                await Task.yield()
            },
            enumerateFiles: { directory, ext in
                let prefix = directory.path(percentEncoded: false) + "/"
                return world.state.withLock { s in
                    s.files.keys.filter { $0.hasPrefix(prefix) && $0.hasSuffix("." + ext) }
                        .sorted().map { URL(filePath: $0) }
                }
            },
            fileInfo: { url in
                let path = url.path(percentEncoded: false)
                return world.state.withLock { s in
                    s.files[path].map { FileInfo(size: $0.count, modified: s.now) }
                }
            },
            readFileRange: { url, offset in
                let path = url.path(percentEncoded: false)
                guard let data = world.state.withLock({ $0.files[path] }) else {
                    throw CocoaError(.fileReadNoSuchFile)
                }
                return offset >= data.count ? Data() : data.subdata(in: offset..<data.count)
            },
            writeFile: { url, data in
                world.state.withLock { $0.files[url.path(percentEncoded: false)] = data }
            }
        )
    }
}

enum Fixtures {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Missing fixture \(name)")
        }
        return data
    }

    static func string(_ name: String) -> String {
        String(decoding: data(name), as: UTF8.self)
    }
}
