import Foundation

/// Codex writes one rollout JSONL per session under `~/.codex/sessions/YYYY/MM/DD/`. The model is
/// named by a `turn_context` record; each API call then logs an `event_msg` of type `token_count`
/// whose `last_token_usage` is the per-call delta. `input_tokens` already includes
/// `cached_input_tokens`, so the cached share is moved out of input for pricing.
public struct CodexLogFormat: UsageLogFormat {
    public let provider: ProviderID = .codex
    public let fileExtension = "jsonl"

    public init() {}

    public func roots(_ environment: HostEnvironment) -> [URL] {
        let home: URL
        if let dir = environment.environmentVariable("CODEX_HOME"), !dir.isEmpty {
            home = environment.path(dir)
        } else {
            home = environment.home.appending(path: ".codex")
        }
        return [home.appending(path: "sessions"), home.appending(path: "archived_sessions")]
    }

    public func event(from line: Substring, carry: inout [String: String]) -> UsageEvent? {
        if line.contains("\"turn_context\"") {
            if let json = try? JSON.parse(Data(line.utf8)), json["type"].string == "turn_context",
               let model = json["payload"]["model"].string {
                carry["model"] = model
            }
            return nil
        }
        guard line.contains("\"token_count\""),
              let json = try? JSON.parse(Data(line.utf8)),
              json["type"].string == "event_msg",
              json["payload"]["type"].string == "token_count" else { return nil }
        let info = json["payload"]["info"]
        let last = info["last_token_usage"]
        guard !last.isNull, let date = json["timestamp"].isoDate else { return nil }

        let input = last["input_tokens"].int ?? 0
        let cached = last["cached_input_tokens"].int ?? 0
        let tokens = TokenTotals(
            input: max(0, input - cached),
            output: last["output_tokens"].int ?? 0,
            cacheWrite: last["cache_write_input_tokens"].int ?? 0,
            cacheRead: cached
        )
        guard tokens.total > 0 else { return nil }
        // The cumulative total identifies the call: a re-emitted count with the same running
        // total carries no new usage.
        let cumulative = info["total_token_usage"]["total_tokens"].int
        return UsageEvent(
            date: date,
            model: carry["model"] ?? "unknown",
            tokens: tokens,
            dedupKey: cumulative.map { "tc:\($0)" }
        )
    }
}
