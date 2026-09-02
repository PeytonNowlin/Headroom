import Foundation

/// Grok Build keeps one directory per session under `~/.grok/sessions/<project>/<id>/`. The
/// `updates.jsonl` transcript logs a `turn_completed` update per turn whose `usage.modelUsage`
/// breaks tokens and `costUsdTicks` (10¹⁰ per dollar) down by model. Subagent sessions are
/// already folded into their parent's turn, so they are skipped.
public struct GrokLogFormat: UsageLogFormat {
    public let provider: ProviderID = .grok
    public let fileExtension = "jsonl"
    static let ticksPerDollar = 10_000_000_000.0

    public init() {}

    public func roots(_ environment: HostEnvironment) -> [URL] {
        if let dir = environment.environmentVariable("GROK_HOME"), !dir.isEmpty {
            return [environment.path(dir).appending(path: "sessions")]
        }
        return [environment.home.appending(path: ".grok/sessions")]
    }

    public func includes(_ file: URL, environment: HostEnvironment) -> Bool {
        guard file.lastPathComponent == "updates.jsonl" else { return false }
        let summary = file.deletingLastPathComponent().appending(path: "summary.json")
        guard environment.fileExists(summary),
              let data = try? environment.readFile(summary),
              let json = try? JSON.parse(data),
              let kind = json["session_kind"].string else { return true }
        return !kind.lowercased().hasPrefix("subagent")
    }

    public func event(from line: Substring, carry: inout [String: String]) -> UsageEvent? {
        guard line.contains("turn_completed"),
              let json = try? JSON.parse(Data(line.utf8)) else { return nil }
        let params = json["params"]
        let update = params["update"]
        guard update["sessionUpdate"].string == "turn_completed" else { return nil }
        let usage = update["usage"]
        guard let models = usage["modelUsage"].object, !models.isEmpty else { return nil }

        let date: Date
        if let ms = params["_meta"]["agentTimestampMs"].double, ms > 0 {
            date = Date(timeIntervalSince1970: ms / 1000)
        } else if let s = json["timestamp"].double, s > 0 {
            date = Date(timeIntervalSince1970: s)
        } else if let iso = json["timestamp"].isoDate {
            date = iso
        } else {
            return nil
        }
        let eventID = params["_meta"]["eventId"].string

        // One event per model; a multi-model turn is emitted as several events on later lines
        // via `carry`, but in practice Grok reports a single model per turn.
        let (model, values) = models.sorted { $0.key < $1.key }[0]
        let input = values["inputTokens"].int ?? 0
        let cacheRead = min(values["cachedReadTokens"].int ?? 0, input)
        let cacheWrite = min(values["cacheCreationTokens"].int ?? 0, input - cacheRead)
        let tokens = TokenTotals(
            input: input - cacheRead - cacheWrite,
            output: values["outputTokens"].int ?? 0,
            cacheWrite: cacheWrite,
            cacheRead: cacheRead
        )
        let ticks = values["costUsdTicks"].double ?? (models.count == 1 ? usage["costUsdTicks"].double : nil)
        return UsageEvent(
            date: date,
            model: model,
            tokens: tokens,
            recordedCost: ticks.map { max(0, $0) / Self.ticksPerDollar },
            dedupKey: eventID.map { "\($0)|\(model)" }
        )
    }
}
