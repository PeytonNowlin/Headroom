import Foundation

/// OpenCode records what each assistant message cost in its own SQLite log, so spend is read from
/// there rather than priced from tokens. Both hosted gateways count — the Go subscription and the
/// Zen pay-as-you-go endpoint; BYO-key traffic through OpenCode bills elsewhere and is skipped.
///
/// An actor for the same reason `CursorSpendSource` is one: the read is slow (a `sqlite3`
/// subprocess per database) and must never happen on the main thread. The result is cached on disk
/// so a relaunch, a locked database, or a failed read still shows yesterday's numbers.
public actor OpenCodeSpendSource {
    public static let interval: TimeInterval = 120
    static let cacheFile = "opencode-spend.json"
    /// The OpenCode-hosted `providerID`s that write an authoritative per-message cost.
    static let hostedProviders = ["opencode", "opencode-go"]
    static let daysBack = 30

    struct Cache: Codable {
        var fetchedAt: Date
        var ledger: SpendLedger
    }

    private let environment: HostEnvironment
    private var cache: Cache?
    private var lastAttempt: Date?

    public init(environment: HostEnvironment) {
        self.environment = environment
        if let data = try? environment.readFile(environment.dataDirectory.appending(path: Self.cacheFile)),
           let cached = try? JSONDecoder.pricing.decode(Cache.self, from: data) {
            cache = cached
        }
    }

    /// True when OpenCode has a local database to read. A directory listing, not a query, so it is
    /// cheap enough for the visibility rules.
    public nonisolated func hasLogs() -> Bool {
        !OpenCodePaths.databases(environment).isEmpty
    }

    /// The current ledger, re-read at most every `interval`. Nil only when OpenCode has never run
    /// here; a failed read returns the cached ledger so the tiles never flash empty.
    public func ledger() async -> SpendLedger? {
        let databases = OpenCodePaths.databases(environment)
        guard !databases.isEmpty else { return nil }
        let now = environment.now()
        if let last = lastAttempt, now.timeIntervalSince(last) < Self.interval {
            return cache?.ledger ?? SpendLedger()
        }
        lastAttempt = now

        let calendar = environment.calendar
        // Start of the oldest tile day, not `now - 30 days`: a wall-clock cutoff sits mid-day and
        // would drop that morning's rows.
        let since = calendar.date(byAdding: .day, value: -(Self.daysBack - 1),
                                  to: calendar.startOfDay(for: now)) ?? now
        let sql = Self.usageSQL(since: since)

        var ledger = SpendLedger()
        var readCount = 0
        for database in databases {
            guard let output = environment.databaseQuery(database, sql) else {
                HeadroomLog.spend.error("opencode usage query failed for \(database.lastPathComponent, privacy: .public)")
                continue
            }
            readCount += 1
            for event in Self.events(from: output, since: since) {
                ledger.add(event, calendar: calendar)
            }
        }
        // Every database refused this pass (locked, permissions): keep the last good numbers.
        guard readCount > 0 else { return cache?.ledger ?? SpendLedger() }

        cache = Cache(fetchedAt: now, ledger: ledger)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cache) {
            try? environment.writeFile(environment.dataDirectory.appending(path: Self.cacheFile), data)
        }
        return ledger
    }

    // MARK: - SQL

    private static let providerFilter = "(" + hostedProviders.map { "'\($0)'" }.joined(separator: ",") + ")"

    /// One row of JSON per database: `[[created_ms, cost, model, input, output, reasoning, write, read], …]`.
    /// The whole result comes back as a single value so one `sqlite3` invocation covers a database.
    static func usageSQL(since: Date) -> String {
        let cutoffMs = Int(since.timeIntervalSince1970 * 1000)
        return """
        SELECT json_group_array(json_array(\
        time_created,\
        json_extract(data,'$.cost'),\
        json_extract(data,'$.modelID'),\
        COALESCE(json_extract(data,'$.tokens.input'),0),\
        COALESCE(json_extract(data,'$.tokens.output'),0),\
        COALESCE(json_extract(data,'$.tokens.reasoning'),0),\
        COALESCE(json_extract(data,'$.tokens.cache.write'),0),\
        COALESCE(json_extract(data,'$.tokens.cache.read'),0))) \
        FROM message \
        WHERE time_created >= \(cutoffMs) \
        AND json_valid(data) \
        AND json_extract(data,'$.role') = 'assistant' \
        AND json_extract(data,'$.providerID') IN \(providerFilter) \
        AND json_type(data,'$.cost') IN ('integer','real');
        """
    }

    // MARK: - Parsing

    /// Rows without a usable timestamp, cost, or model are dropped at this boundary rather than
    /// counted as zero. Reasoning tokens join output so the total matches OpenCode's own.
    static func events(from output: String, since: Date) -> [UsageEvent] {
        guard let array = (try? JSON.parse(Data(output.utf8)))?.array else { return [] }
        var events: [UsageEvent] = []
        events.reserveCapacity(array.count)
        for row in array {
            guard let createdMs = row[0].double, let cost = row[1].double, cost >= 0,
                  let model = row[2].string, !model.isEmpty else { continue }
            let date = Date(timeIntervalSince1970: createdMs / 1000)
            guard date >= since else { continue }
            let tokens = TokenTotals(
                input: count(row[3]),
                output: count(row[4]) + count(row[5]),
                cacheWrite: count(row[6]),
                cacheRead: count(row[7])
            )
            events.append(UsageEvent(date: date, model: model, tokens: tokens, recordedCost: cost))
        }
        return events
    }

    /// Clamped before the `Int` conversion: `Int(Double)` traps above `Int.max`, and a corrupt row
    /// should not be able to crash a refresh.
    private static func count(_ json: JSON) -> Int {
        Int(min(max(json.double ?? 0, 0), 1e15))
    }
}
