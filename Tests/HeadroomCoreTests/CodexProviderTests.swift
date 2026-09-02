import Foundation
import HeadroomCore
import Testing

private let usageURL = "https://chatgpt.com/backend-api/wham/usage"
private let creditsURL = "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"

/// A structurally valid JWT whose payload carries `exp`; the signature is garbage.
private func jwt(exp: Date) -> String {
    let header = Data(#"{"alg":"RS256","typ":"JWT"}"#.utf8).base64URL
    let payload = Data(#"{"exp":\#(Int(exp.timeIntervalSince1970)),"sub":"u"}"#.utf8).base64URL
    return "\(header).\(payload).sig"
}

private func authJSON(token: String, accountID: String = "acct-123") -> String {
    """
    {"tokens":{"access_token":"\(token)","refresh_token":"rt","id_token":"id","account_id":"\(accountID)"},"last_refresh":"2026-09-01T00:00:00Z"}
    """
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

@Suite("Codex provider")
struct CodexProviderTests {
    @Test("reads auth.json, sends the account header, and humanizes the plan")
    func basics() async throws {
        let world = TestWorld()
        world.file(".codex/auth.json", authJSON(token: "tok", accountID: "acct-9"))
        world.respond(usageURL, fixture: "codex-usage-weekly-primary.json")
        world.respond(creditsURL, status: 404, json: "{}")

        let snapshot = try await CodexProvider(environment: world.environment).refresh()

        let usage = world.requests.first { $0.url.absoluteString == usageURL }
        #expect(usage?.headers["Authorization"] == "Bearer tok")
        #expect(usage?.headers["ChatGPT-Account-Id"] == "acct-9")
        #expect(snapshot.status == .connected)
        #expect(snapshot.planName == "Business Prolite")
    }

    @Test("a weekly window in the primary slot is still Weekly, and a null secondary is skipped")
    func durationClassification() async throws {
        let world = TestWorld()
        world.file(".codex/auth.json", authJSON(token: "tok"))
        world.respond(usageURL, fixture: "codex-usage-weekly-primary.json")
        world.respond(creditsURL, status: 404, json: "{}")

        let snapshot = try await CodexProvider(environment: world.environment).refresh()
        #expect(snapshot.windows.map(\.id) == ["weekly"])
        #expect(snapshot.windows[0].title == "Weekly")
        #expect(snapshot.windows[0].usedPercent == 1)
        #expect(snapshot.windows[0].duration == 604_800)
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_788_783_772))
    }

    @Test("both windows plus Spark limits map to four rows; ring follows the hottest")
    func fullPayload() async throws {
        let world = TestWorld()
        world.file(".codex/auth.json", authJSON(token: "tok"))
        world.respond(usageURL, fixture: "codex-usage-full.json")
        world.respond(creditsURL, fixture: "codex-credits.json")

        let snapshot = try await CodexProvider(environment: world.environment).refresh()
        #expect(snapshot.windows.map(\.id) == ["session", "weekly", "spark:session", "spark:weekly"])
        #expect(snapshot.windows.map(\.title) == ["Session", "Weekly", "Spark", "Spark Weekly"])
        #expect(snapshot.ringUsedPercent == 72)
        #expect(snapshot.planName == "Pro")
        #expect(snapshot.extraUsage == ExtraUsage(isEnabled: true, label: "$31.84 credits"))
    }

    @Test("reset-credit count prefers the dedicated endpoint and falls back to the usage body")
    func resetCredits() async throws {
        let world = TestWorld()
        world.file(".codex/auth.json", authJSON(token: "tok"))
        world.respond(usageURL, fixture: "codex-usage-full.json")
        world.respond(creditsURL, fixture: "codex-credits.json")
        let dedicated = try await CodexProvider(environment: world.environment).refresh()
        #expect(dedicated.resetCredits == 2)

        let fallback = TestWorld()
        fallback.file(".codex/auth.json", authJSON(token: "tok"))
        fallback.respond(usageURL, fixture: "codex-usage-full.json")
        fallback.respond(creditsURL, status: 500, json: "{}")
        let fromBody = try await CodexProvider(environment: fallback.environment).refresh()
        #expect(fromBody.resetCredits == 1)
        #expect(fromBody.status == .connected)
    }

    @Test("CODEX_HOME relocates the auth file; missing file is absent; 401 is expired")
    func credentialStates() async throws {
        let relocated = TestWorld()
        relocated.env("CODEX_HOME", "/Users/test/alt-codex")
        relocated.absoluteFile("/Users/test/alt-codex/auth.json", authJSON(token: "alt"))
        relocated.respond(usageURL, fixture: "codex-usage-weekly-primary.json")
        relocated.respond(creditsURL, status: 404, json: "{}")
        let ok = try await CodexProvider(environment: relocated.environment).refresh()
        #expect(ok.status == .connected)
        #expect(relocated.requests[0].headers["Authorization"] == "Bearer alt")

        let none = TestWorld()
        let provider = CodexProvider(environment: none.environment)
        #expect(provider.hasLocalCredentials() == false)
        #expect(try await provider.refresh().status == .absent)

        let rejected = TestWorld()
        rejected.file(".codex/auth.json", authJSON(token: "bad"))
        rejected.respond(usageURL, status: 401, json: #"{"detail":"Unauthorized"}"#)
        #expect(try await CodexProvider(environment: rejected.environment).refresh().status == .expired)
    }

    @Test("a JWT past its exp is expired without a network call")
    func jwtExpiry() async throws {
        let world = TestWorld()
        world.file(".codex/auth.json", authJSON(token: jwt(exp: world.now.addingTimeInterval(-120))))
        let snapshot = try await CodexProvider(environment: world.environment).refresh()
        #expect(snapshot.status == .expired)
        #expect(world.requests.isEmpty)

        let fresh = TestWorld()
        fresh.file(".codex/auth.json", authJSON(token: jwt(exp: fresh.now.addingTimeInterval(3600))))
        fresh.respond(usageURL, fixture: "codex-usage-weekly-primary.json")
        fresh.respond(creditsURL, status: 404, json: "{}")
        #expect(try await CodexProvider(environment: fresh.environment).refresh().status == .connected)
    }
}
