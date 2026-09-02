import Foundation

/// Cursor writes no local usage log, so spend comes from the dashboard's usage-events CSV export,
/// priced locally from the exported token counts like every other provider.
enum CursorUsageCSV {
    enum Column {
        static let date = "Date"
        static let model = "Model"
        static let cacheWrite = "Input (w/ Cache Write)"
        static let input = "Input (w/o Cache Write)"
        static let cacheRead = "Cache Read"
        static let output = "Output Tokens"
        static let required = [date, model, cacheWrite, input, cacheRead, output]
    }

    enum ParseError: Error, Equatable {
        case missingColumns([String])
        case malformed
    }

    struct Result: Equatable {
        var events: [UsageEvent]
        var rejectedRows: Int
    }

    private static let plainDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Rows are per-model aggregates, so there is no dedup key and no long-context or Max Mode
    /// uplift; each row bills at the base model rate. Empty numeric cells are zero; anything
    /// non-numeric or negative rejects that row rather than silently counting as zero.
    static func parse(_ text: String) throws -> Result {
        var events: [UsageEvent] = []
        var rejected = 0
        var missing = Column.required
        var duplicateColumns = false
        let summary = CSV.forEachRecord(in: text, header: { header in
            let available = Set(header)
            missing = Column.required.filter { !available.contains($0) }
            duplicateColumns = available.count != header.count
        }) { row in
            guard let rawDate = row[Column.date]?.trimmingCharacters(in: .whitespaces), !rawDate.isEmpty,
                  let date = parseDate(rawDate),
                  let model = row[Column.model]?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty,
                  let cacheWrite = parseCount(row[Column.cacheWrite]),
                  let input = parseCount(row[Column.input]),
                  let cacheRead = parseCount(row[Column.cacheRead]),
                  let output = parseCount(row[Column.output]) else {
                rejected += 1
                return
            }
            events.append(UsageEvent(
                date: date, model: model,
                tokens: TokenTotals(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
            ))
        }
        guard summary.isWellFormed, !duplicateColumns else { throw ParseError.malformed }
        guard missing.isEmpty else { throw ParseError.missingColumns(missing) }
        return Result(events: events, rejectedRows: rejected + summary.rejectedRecords)
    }

    private static func parseDate(_ raw: String) -> Date? {
        DateParsing.iso8601(raw) ?? plainDateTime.date(from: raw)
    }

    /// `1,234,567` and `1234567` are both fine; `1.5`, `-3`, and `12,34` are not.
    private static func parseCount(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return 0 }
        let groups = s.split(separator: ",", omittingEmptySubsequences: false)
        let digits: (Substring) -> Bool = { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), digits(groups[0]),
                  groups.dropFirst().allSatisfy({ $0.count == 3 && digits($0) }) else { return nil }
        } else if !digits(groups[0]) {
            return nil
        }
        return Int(groups.joined())
    }
}

/// Fetches the last 30 days of Cursor usage events and keeps the resulting ledger on disk so a
/// relaunch (or a failed fetch) still has yesterday's numbers.
public actor CursorSpendSource {
    public static let exportURL = URL(string: "https://cursor.com/api/dashboard/export-usage-events-csv")!
    public static let interval: TimeInterval = 5 * 60
    static let cacheFile = "cursor-spend.json"

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

    /// True when there is a Cursor login to fetch for. Cheap and synchronous for visibility rules.
    public nonisolated func hasCredentials() -> Bool {
        CursorCredentialStore(environment: environment).accessToken() != nil
    }

    /// The current ledger, refetched at most every `interval`. Nil only when there is no login;
    /// a failed fetch returns the cached ledger (possibly empty) so callers can still total.
    public func ledger() async -> SpendLedger? {
        guard let token = CursorCredentialStore(environment: environment).accessToken() else { return nil }
        let now = environment.now()
        if let last = lastAttempt, now.timeIntervalSince(last) < Self.interval {
            return cache?.ledger ?? SpendLedger()
        }
        lastAttempt = now

        guard let session = CursorSession(accessToken: token) else { return cache?.ledger ?? SpendLedger() }
        let calendar = environment.calendar
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        var request = CursorProvider.restRequest(Self.exportURL, query: [
            "startDate": String(Int(start.timeIntervalSince1970 * 1000)),
            "endDate": String(Int(now.timeIntervalSince1970 * 1000)),
            "strategy": "tokens",
        ], session: session)
        request.headers["Accept"] = "text/csv"

        guard let response = try? await environment.send(request), response.isSuccess,
              let text = String(data: response.body, encoding: .utf8) else {
            HeadroomLog.spend.error("cursor usage export request failed")
            return cache?.ledger ?? SpendLedger()
        }
        do {
            let parsed = try CursorUsageCSV.parse(text)
            if parsed.rejectedRows > 0 {
                HeadroomLog.spend.notice("cursor usage export skipped \(parsed.rejectedRows) malformed rows")
            }
            var ledger = SpendLedger()
            for event in parsed.events { ledger.add(event, calendar: calendar) }
            cache = Cache(fetchedAt: now, ledger: ledger)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(cache) {
                try? environment.writeFile(environment.dataDirectory.appending(path: Self.cacheFile), data)
            }
            return ledger
        } catch {
            HeadroomLog.spend.error("cursor usage export unusable: \(String(describing: error), privacy: .public)")
            return cache?.ledger ?? SpendLedger()
        }
    }
}
