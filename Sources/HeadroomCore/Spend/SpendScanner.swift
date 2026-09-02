import Foundation

/// How one provider's local session logs are found and read.
public protocol UsageLogFormat: Sendable {
    var provider: ProviderID { get }
    var fileExtension: String { get }
    func roots(_ environment: HostEnvironment) -> [URL]
    /// Parse one line. Return nil for lines that carry no usage. `carry` is per-file state
    /// (e.g. the model named by an earlier record) and persists across incremental scans.
    func event(from line: Substring, carry: inout [String: String]) -> UsageEvent?
}

/// Incrementally scans a provider's logs into a `SpendLedger`, remembering per-file progress so a
/// rescan only reads appended bytes. Files untouched for longer than the 30-day window are skipped.
public actor SpendScanner {
    struct FileProgress: Codable {
        var size: Int
        var ledger: SpendLedger
        /// Dedup keys from the tail of the last read, so a record streamed across two scans is
        /// still counted once.
        var tailKeys: [String]
        var carry: [String: String]

        init(size: Int, ledger: SpendLedger, tailKeys: [String], carry: [String: String] = [:]) {
            self.size = size
            self.ledger = ledger
            self.tailKeys = tailKeys
            self.carry = carry
        }

        // Tolerate fields added after a cache was written; a decode failure would force a full
        // rescan of every session file.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            size = try c.decode(Int.self, forKey: .size)
            ledger = try c.decode(SpendLedger.self, forKey: .ledger)
            tailKeys = try c.decodeIfPresent([String].self, forKey: .tailKeys) ?? []
            carry = try c.decodeIfPresent([String: String].self, forKey: .carry) ?? [:]
        }
    }

    struct Cache: Codable {
        var files: [String: FileProgress] = [:]
    }

    private let format: any UsageLogFormat
    private let environment: HostEnvironment
    private var cache: Cache
    private let cacheURL: URL
    static let maxAge: TimeInterval = 31 * 86400
    static let tailKeyCount = 64

    public init(format: any UsageLogFormat, environment: HostEnvironment) {
        self.format = format
        self.environment = environment
        cacheURL = environment.dataDirectory.appending(path: "spend-\(format.provider.rawValue).json")
        if let data = try? environment.readFile(cacheURL),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            self.cache = cache
        } else {
            cache = Cache()
        }
    }

    /// Whether any log directory exists; used to decide if spend tiles should appear at all.
    public nonisolated func hasLogs() -> Bool {
        format.roots(environment).contains { environment.fileExists($0) }
    }

    public func scan() -> SpendLedger {
        let now = environment.now()
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        var seen: Set<String> = []

        for root in format.roots(environment) {
            for url in environment.enumerateFiles(root, format.fileExtension) {
                let path = url.path(percentEncoded: false)
                seen.insert(path)
                guard let info = environment.fileInfo(url) else { continue }
                var progress = cache.files[path]
                if progress == nil, info.modified < cutoff { continue }
                if let p = progress, p.size == info.size { continue }
                if let p = progress, p.size > info.size { progress = nil }
                // JSONSerialization leaves autoreleased objects behind; drain per file so a
                // first full scan of hundreds of sessions doesn't balloon resident memory.
                cache.files[path] = autoreleasepool { read(url, from: progress) }
            }
        }

        cache.files = cache.files.filter { seen.contains($0.key) }
        var ledger = SpendLedger()
        for progress in cache.files.values { ledger.merge(progress.ledger) }
        ledger.dropDays(before: SpendLedger.dayKey(cutoff, calendar: environment.calendar))
        persist()
        return ledger
    }

    private func read(_ url: URL, from previous: FileProgress?) -> FileProgress {
        var progress = previous ?? FileProgress(size: 0, ledger: SpendLedger(), tailKeys: [])
        guard let data = try? environment.readFileRange(url, progress.size), !data.isEmpty else { return progress }

        // Only consume complete lines; a partial trailing line is picked up next scan.
        var consumable = data
        if data.last != UInt8(ascii: "\n") {
            guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return progress }
            consumable = data[data.startIndex...lastNewline]
        }

        var recent = progress.tailKeys
        var recentSet = Set(recent)
        let text = String(decoding: consumable, as: UTF8.self)
        let calendar = environment.calendar
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let event = format.event(from: line, carry: &progress.carry) else { continue }
            if let key = event.dedupKey {
                if recentSet.contains(key) { continue }
                recent.append(key)
                recentSet.insert(key)
                if recent.count > Self.tailKeyCount * 4 {
                    let dropped = recent.removeFirst(recent.count - Self.tailKeyCount)
                    _ = dropped
                    recentSet = Set(recent)
                }
            }
            progress.ledger.add(event, calendar: calendar)
        }
        progress.size += consumable.count
        progress.tailKeys = Array(recent.suffix(Self.tailKeyCount))
        return progress
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            try? environment.writeFile(cacheURL, data)
        }
    }
}

private extension Array {
    mutating func removeFirst(_ k: Int) -> [Element] {
        let out = Array(prefix(k))
        removeSubrange(0..<k)
        return out
    }
}
