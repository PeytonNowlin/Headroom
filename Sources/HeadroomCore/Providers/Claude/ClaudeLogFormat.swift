import Foundation

/// Claude Code writes one JSONL per session under `~/.claude/projects/<slug>/`. Assistant records
/// carry `message.usage`; a streamed reply is logged several times with the same `message.id`.
public struct ClaudeLogFormat: UsageLogFormat {
    public let provider: ProviderID = .claude
    public let fileExtension = "jsonl"

    public init() {}

    public func roots(_ environment: HostEnvironment) -> [URL] {
        var roots: [URL] = []
        if let dir = environment.environmentVariable("CLAUDE_CONFIG_DIR"), !dir.isEmpty {
            roots.append(environment.path(dir).appending(path: "projects"))
        }
        roots.append(environment.home.appending(path: ".claude/projects"))
        roots.append(environment.home.appending(path: ".config/claude/projects"))
        return roots
    }

    public func event(from line: Substring, carry: inout [String: String]) -> UsageEvent? {
        // Cheap pre-filter before paying for JSON parsing.
        guard line.contains("\"usage\""), line.contains("\"assistant\"") else { return nil }
        guard let json = try? JSON.parse(Data(line.utf8)), json["type"].string == "assistant" else { return nil }
        let message = json["message"]
        let usage = message["usage"]
        guard !usage.isNull, let model = message["model"].string, model != "<synthetic>",
              let date = json["timestamp"].isoDate else { return nil }
        let tokens = TokenTotals(
            input: usage["input_tokens"].int ?? 0,
            output: usage["output_tokens"].int ?? 0,
            cacheWrite: usage["cache_creation_input_tokens"].int ?? 0,
            cacheRead: usage["cache_read_input_tokens"].int ?? 0
        )
        let key = message["id"].string ?? json["requestId"].string ?? json["uuid"].string
        return UsageEvent(date: date, model: model, tokens: tokens, dedupKey: key)
    }
}
