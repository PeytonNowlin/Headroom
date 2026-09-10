import Foundation
import HeadroomCore
import Testing

private let usageURL = "https://opencode.ai/zen/go/v1/usage"
private let authPath = ".local/share/opencode/auth.json"

private func authJSON(goKey: String?) -> String {
    let go = goKey.map { #","opencode-go":{"type":"api","key":"\#($0)"}"# } ?? ""
    return #"{"opencode":{"type":"api","key":"zen-key"}\#(go)}"#
}

private let usageBody = """
{"usage":{
  "rolling":{"percent":18.5,"resetsAt":"2026-09-01T15:00:00Z"},
  "weekly":{"percent":63,"resetsAt":"2026-09-07T00:00:00Z"},
  "monthly":{"percent":41.25,"resetsAt":"2026-09-24T00:00:00Z"}}}
"""

@Suite("OpenCode provider")
struct OpenCodeProviderTests {
    @Test("reads the opencode-go key, sends it as a bearer, maps the three Go windows")
    func goWindows() async throws {
        let world = TestWorld()
        world.file(authPath, authJSON(goKey: "og-1"))
        world.respond(usageURL, json: usageBody)

        let snapshot = try await OpenCodeProvider(environment: world.environment).refresh()

        let request = world.requests.first { $0.url.absoluteString == usageURL }
        #expect(request?.headers["Authorization"] == "Bearer og-1")
        #expect(snapshot.status == .connected)
        #expect(snapshot.planName == "Go")
        #expect(snapshot.windows.map(\.id) == ["session", "weekly", "monthly"])
        #expect(snapshot.windows.map(\.title) == ["Session", "Weekly", "Monthly"])
        #expect(snapshot.windows[0].usedPercent == 18.5)
        #expect(snapshot.windows[0].duration == QuotaWindow.sessionDuration)
        #expect(snapshot.windows[1].resetsAt == DateParsing.iso8601("2026-09-07T00:00:00Z"))
        #expect(snapshot.windows[1].duration == QuotaWindow.weeklyDuration)
        #expect(snapshot.ringUsedPercent == 63)
    }

    @Test("a Zen-only key is connected with a note, not an error; percents clamp; no reset is not started")
    func zenOnlyAndEdges() async throws {
        let zen = TestWorld()
        zen.file(authPath, authJSON(goKey: "og-1"))
        zen.respond(usageURL, status: 403,
                    json: #"{"error":{"type":"EntitlementError","message":"no go subscription"}}"#)
        let snapshot = try await OpenCodeProvider(environment: zen.environment).refresh()
        #expect(snapshot.status == .connected)
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.ringUsedPercent == nil)
        #expect(snapshot.note?.contains("No OpenCode Go subscription") == true)

        let partial = TestWorld()
        partial.file(authPath, authJSON(goKey: "og-1"))
        partial.respond(usageURL, json: #"{"usage":{"rolling":{"percent":0},"weekly":{"percent":140}}}"#)
        let s = try await OpenCodeProvider(environment: partial.environment).refresh()
        #expect(s.windows.map(\.id) == ["session", "weekly"])
        #expect(s.windows[0].isStarted == false)
        #expect(s.windows[1].usedPercent == 100)
    }

    @Test("401 is expired, no key is absent, a body without windows is malformed, 5xx retries")
    func statuses() async throws {
        let rejected = TestWorld()
        rejected.file(authPath, authJSON(goKey: "og-1"))
        rejected.respond(usageURL, status: 401, json: #"{"error":{"type":"AuthError"}}"#)
        #expect(try await OpenCodeProvider(environment: rejected.environment).refresh().status == .expired)

        let zenOnlyFile = TestWorld()
        zenOnlyFile.file(authPath, authJSON(goKey: nil))
        let absent = try await OpenCodeProvider(environment: zenOnlyFile.environment).refresh()
        #expect(absent.status == .absent)
        #expect(zenOnlyFile.requests.isEmpty)
        #expect(OpenCodeProvider(environment: zenOnlyFile.environment).hasLocalCredentials() == false)

        let empty = TestWorld()
        empty.file(authPath, authJSON(goKey: "og-1"))
        empty.respond(usageURL, json: #"{"usage":{}}"#)
        await #expect(throws: ProviderError.self) {
            try await OpenCodeProvider(environment: empty.environment).refresh()
        }

        let down = TestWorld()
        down.file(authPath, authJSON(goKey: "og-1"))
        down.respond(usageURL, status: 503, json: "{}")
        await #expect(throws: ProviderError.transient(statusCode: 503)) {
            try await OpenCodeProvider(environment: down.environment).refresh()
        }
    }

    @Test("OPENCODE_DATA_DIR and XDG_DATA_HOME move the auth file")
    func dataDirectoryOverrides() async throws {
        let explicit = TestWorld()
        explicit.env("OPENCODE_DATA_DIR", "~/oc-data")
        explicit.file("oc-data/auth.json", authJSON(goKey: "og-2"))
        explicit.respond(usageURL, json: usageBody)
        _ = try await OpenCodeProvider(environment: explicit.environment).refresh()
        #expect(explicit.requests.first?.headers["Authorization"] == "Bearer og-2")

        let xdg = TestWorld()
        xdg.env("XDG_DATA_HOME", "~/share")
        xdg.file("share/opencode/auth.json", authJSON(goKey: "og-3"))
        xdg.respond(usageURL, json: usageBody)
        _ = try await OpenCodeProvider(environment: xdg.environment).refresh()
        #expect(xdg.requests.first?.headers["Authorization"] == "Bearer og-3")
    }
}
