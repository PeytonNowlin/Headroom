import Foundation

public struct TokenTotals: Sendable, Equatable, Codable, AdditiveArithmetic {
    public var input: Int
    public var output: Int
    public var cacheWrite: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public static let zero = TokenTotals()
    public var total: Int { input + output + cacheWrite + cacheRead }

    public static func + (l: TokenTotals, r: TokenTotals) -> TokenTotals {
        TokenTotals(input: l.input + r.input, output: l.output + r.output,
                    cacheWrite: l.cacheWrite + r.cacheWrite, cacheRead: l.cacheRead + r.cacheRead)
    }

    public static func - (l: TokenTotals, r: TokenTotals) -> TokenTotals {
        TokenTotals(input: l.input - r.input, output: l.output - r.output,
                    cacheWrite: l.cacheWrite - r.cacheWrite, cacheRead: l.cacheRead - r.cacheRead)
    }

    enum CodingKeys: String, CodingKey { case input = "i", output = "o", cacheWrite = "w", cacheRead = "r" }
}

/// One priced API call parsed from a local log.
public struct UsageEvent: Sendable, Equatable {
    public var date: Date
    public var model: String
    public var tokens: TokenTotals
    /// Provider-recorded cost, used instead of pricing when present.
    public var recordedCost: Double?
    /// Stable identity for de-duplicating streamed or re-logged records.
    public var dedupKey: String?

    public init(date: Date, model: String, tokens: TokenTotals, recordedCost: Double? = nil, dedupKey: String? = nil) {
        self.date = date
        self.model = model
        self.tokens = tokens
        self.recordedCost = recordedCost
        self.dedupKey = dedupKey
    }
}

/// Token totals bucketed by local calendar day, then by model. Pricing is applied at read time so
/// a price-list update reprices history without a rescan.
public struct SpendLedger: Sendable, Equatable, Codable {
    public struct ModelDay: Sendable, Equatable, Codable {
        public var tokens: TokenTotals = .zero
        public var recordedCost: Double = 0
        public var calls: Int = 0
        public init() {}
    }

    /// `yyyy-MM-dd` (local) → model → totals.
    public var days: [String: [String: ModelDay]]

    public init(days: [String: [String: ModelDay]] = [:]) {
        self.days = days
    }

    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public mutating func add(_ event: UsageEvent, calendar: Calendar) {
        let key = Self.dayKey(event.date, calendar: calendar)
        var day = days[key]?[event.model] ?? ModelDay()
        day.tokens += event.tokens
        day.recordedCost += event.recordedCost ?? 0
        day.calls += 1
        days[key, default: [:]][event.model] = day
    }

    public mutating func merge(_ other: SpendLedger) {
        for (key, models) in other.days {
            for (model, day) in models {
                var mine = days[key]?[model] ?? ModelDay()
                mine.tokens += day.tokens
                mine.recordedCost += day.recordedCost
                mine.calls += day.calls
                days[key, default: [:]][model] = mine
            }
        }
    }

    public mutating func dropDays(before cutoff: String) {
        days = days.filter { $0.key >= cutoff }
    }
}

/// One tile: cost and tokens over a window. `hasData` is false when no records fall in the
/// window at all, which renders as "No data" rather than "$0.00".
public struct SpendTile: Sendable, Equatable, Codable {
    public var cost: Double
    public var tokens: Int
    public var calls: Int
    public var hasData: Bool
    /// Tokens whose model had no price; still counted in `tokens`, excluded from `cost`.
    public var unpricedTokens: Int

    public init(cost: Double = 0, tokens: Int = 0, calls: Int = 0, hasData: Bool = false, unpricedTokens: Int = 0) {
        self.cost = cost
        self.tokens = tokens
        self.calls = calls
        self.hasData = hasData
        self.unpricedTokens = unpricedTokens
    }

    public static let empty = SpendTile()

    public static func + (l: SpendTile, r: SpendTile) -> SpendTile {
        SpendTile(cost: l.cost + r.cost, tokens: l.tokens + r.tokens, calls: l.calls + r.calls,
                  hasData: l.hasData || r.hasData, unpricedTokens: l.unpricedTokens + r.unpricedTokens)
    }
}

public struct SpendSummary: Sendable, Equatable, Codable {
    public var today: SpendTile
    public var yesterday: SpendTile
    public var last30Days: SpendTile
    /// Daily cost for the last 30 days, oldest first; used for pace/trend.
    public var dailyCost: [Double]
    public var computedAt: Date

    public init(today: SpendTile, yesterday: SpendTile, last30Days: SpendTile, dailyCost: [Double], computedAt: Date) {
        self.today = today
        self.yesterday = yesterday
        self.last30Days = last30Days
        self.dailyCost = dailyCost
        self.computedAt = computedAt
    }

    public static func + (l: SpendSummary, r: SpendSummary) -> SpendSummary {
        SpendSummary(
            today: l.today + r.today, yesterday: l.yesterday + r.yesterday,
            last30Days: l.last30Days + r.last30Days,
            dailyCost: zip(l.dailyCost, r.dailyCost).map(+),
            computedAt: max(l.computedAt, r.computedAt)
        )
    }
}

public enum SpendSummarizer {
    public static func summarize(_ ledger: SpendLedger, pricing: PricingTable, now: Date, calendar: Calendar) -> SpendSummary {
        let todayStart = calendar.startOfDay(for: now)
        func key(daysAgo n: Int) -> String {
            SpendLedger.dayKey(calendar.date(byAdding: .day, value: -n, to: todayStart)!, calendar: calendar)
        }
        func tile(_ keys: [String]) -> SpendTile {
            var t = SpendTile()
            for k in keys {
                guard let models = ledger.days[k] else { continue }
                t.hasData = true
                for (model, day) in models {
                    t.tokens += day.tokens.total
                    t.calls += day.calls
                    if day.recordedCost > 0 {
                        t.cost += day.recordedCost
                    } else if let price = pricing.price(for: model) {
                        t.cost += price.cost(of: day.tokens)
                    } else {
                        t.unpricedTokens += day.tokens.total
                    }
                }
            }
            return t
        }
        let last30 = (0..<30).reversed().map { key(daysAgo: $0) }
        return SpendSummary(
            today: tile([key(daysAgo: 0)]),
            yesterday: tile([key(daysAgo: 1)]),
            last30Days: tile(last30),
            dailyCost: last30.map { tile([$0]).cost },
            computedAt: now
        )
    }
}
