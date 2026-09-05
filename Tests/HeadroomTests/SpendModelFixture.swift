import Foundation
import HeadroomCore
import Synchronization

final class SpendModelFixture: Sendable {
    let hasLogs = Mutex(true)
    var environment: HostEnvironment {
        let now = Date(timeIntervalSince1970: 1_788_624_000)
        let home = URL(filePath: "/tmp/headroom-synthetic-trends")
        let file = home.appending(path: ".claude/projects/example/session.jsonl")
        let records = (0..<30).filter { $0 % 4 != 1 }.map { day in
            let date = now.addingTimeInterval(-Double(day) * 86400).ISO8601Format()
            let model = day % 2 == 0 ? "claude-sonnet-5" : "unknown-preview"
            return "{\"type\":\"assistant\",\"timestamp\":\"\(date)\",\"message\":{\"id\":\"m\(day)\",\"model\":\"\(model)\",\"usage\":{\"input_tokens\":\(100000 + day * 2500),\"output_tokens\":30000}}}\n"
        }.joined().data(using: .utf8)!
        return HostEnvironment(home: home, timeZone: .gmt,
            readFile: { _ in throw CocoaError(.fileReadNoSuchFile) },
            fileExists: { [self] in $0.path.contains(".claude/projects") && hasLogs.withLock { $0 } },
            keychainPassword: { _ in nil }, environmentVariable: { _ in nil },
            send: { _ in HTTPResponse(statusCode: 503) }, now: { now },
            sleep: { try await Task.sleep(for: $0) },
            enumerateFiles: { [self] root, _ in root.path.contains(".claude/projects") && hasLogs.withLock { $0 } ? [file] : [] },
            fileInfo: { _ in FileInfo(size: records.count, modified: now) },
            readFileRange: { _, offset in Data(records.dropFirst(offset)) })
    }
}
