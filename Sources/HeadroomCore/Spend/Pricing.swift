import Foundation
import Synchronization

/// Per-token USD prices for one model.
public struct ModelPrice: Sendable, Equatable, Codable {
    public var input: Double
    public var output: Double
    public var cacheWrite: Double
    public var cacheRead: Double

    public init(input: Double, output: Double, cacheWrite: Double = 0, cacheRead: Double = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public func cost(of tokens: TokenTotals) -> Double {
        Double(tokens.input) * input
            + Double(tokens.output) * output
            + Double(tokens.cacheWrite) * cacheWrite
            + Double(tokens.cacheRead) * cacheRead
    }

    enum CodingKeys: String, CodingKey { case input = "i", output = "o", cacheWrite = "w", cacheRead = "r" }
}

/// Maps a vendor-specific slug (Cursor's `claude-4.6-opus-high-thinking`, `composer`) to the
/// catalog name that carries its price.
public struct AliasRule: Sendable, Equatable, Codable {
    public var pattern: String
    public var canonical: String

    public init(pattern: String, canonical: String) {
        self.pattern = pattern
        self.canonical = canonical
    }
}

public struct PricingTable: Sendable, Equatable, Codable {
    public var updated: Date?
    public var models: [String: ModelPrice]
    /// Tried in order before any name-based lookup.
    public var aliases: [AliasRule]
    /// `-fast` variants bill the base model's rates times this; unlisted bases stay unpriced.
    public var fastMultipliers: [String: Double]

    public init(updated: Date? = nil, models: [String: ModelPrice], aliases: [AliasRule] = [], fastMultipliers: [String: Double] = [:]) {
        self.updated = updated
        self.models = models
        self.aliases = aliases
        self.fastMultipliers = fastMultipliers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updated = try c.decodeIfPresent(Date.self, forKey: .updated)
        models = try c.decode([String: ModelPrice].self, forKey: .models)
        aliases = try c.decodeIfPresent([AliasRule].self, forKey: .aliases) ?? []
        fastMultipliers = try c.decodeIfPresent([String: Double].self, forKey: .fastMultipliers) ?? [:]
    }

    /// Alias rules first, then exact match, then progressively looser forms: provider prefix
    /// stripped, date suffix stripped, `-latest` stripped, and finally `-fast` priced as a multiple.
    public func price(for model: String) -> ModelPrice? {
        let name = canonicalName(for: model) ?? model
        for candidate in Self.candidates(for: name) {
            if let p = models[candidate] { return p }
        }
        if name.hasSuffix("-fast") {
            let base = String(name.dropLast(5))
            if let multiplier = fastMultipliers[base] ?? fastMultipliers[Self.candidates(for: base).first { models[$0] != nil } ?? ""],
               let price = price(for: base) {
                return ModelPrice(input: price.input * multiplier, output: price.output * multiplier,
                                  cacheWrite: price.cacheWrite * multiplier, cacheRead: price.cacheRead * multiplier)
            }
        }
        return nil
    }

    /// The first alias rule matching the whole slug, if any.
    public func canonicalName(for model: String) -> String? {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        for rule in aliases where AliasRegex.matches(rule.pattern, trimmed) {
            return rule.canonical
        }
        return nil
    }

    static func candidates(for model: String) -> [String] {
        var out = [model]
        var m = model.lowercased()
        if m != model { out.append(m) }
        if let slash = m.lastIndex(of: "/") {
            m = String(m[m.index(after: slash)...])
            out.append(m)
        }
        if let range = m.range(of: #"-\d{8}$"#, options: .regularExpression) {
            m.removeSubrange(range)
            out.append(m)
        }
        for suffix in ["-latest", "-build"] where m.hasSuffix(suffix) {
            m.removeLast(suffix.count)
            out.append(m)
        }
        return out
    }

    /// Entries in `other` win; its alias rules are consulted first.
    public func merging(_ other: PricingTable) -> PricingTable {
        PricingTable(updated: other.updated ?? updated,
                     models: models.merging(other.models) { $1 },
                     aliases: other.aliases + aliases.filter { rule in !other.aliases.contains(rule) },
                     fastMultipliers: fastMultipliers.merging(other.fastMultipliers) { $1 })
    }

    /// The snapshot compiled into the app, for first launch and offline use.
    public static func bundled() -> PricingTable {
        var table = PricingTable(models: [:])
        if let url = Bundle.module.url(forResource: "pricing", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder.pricing.decode(PricingTable.self, from: data) {
            table = decoded
        }
        if let url = Bundle.module.url(forResource: "pricing-supplement", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let supplement = try? PricingSource.supplement(data, at: nil) {
            table = table.merging(supplement)
        }
        return table
    }
}

/// Compiled alias patterns, shared across lookups.
enum AliasRegex {
    private static let cache = Mutex<[String: NSRegularExpression]>([:])

    static func matches(_ pattern: String, _ text: String) -> Bool {
        let regex = cache.withLock { cache -> NSRegularExpression? in
            if let r = cache[pattern] { return r }
            guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
            cache[pattern] = r
            return r
        }
        guard let regex else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}

public extension JSONDecoder {
    static var pricing: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Parsers for the two public price lists we track.
public enum PricingSource {
    public static let liteLLMURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    public static let modelsDevURL = URL(string: "https://models.dev/api.json")!

    static let providers: Set<String> = ["anthropic", "openai", "xai"]

    /// LiteLLM: flat map of model → `*_cost_per_token` fields.
    public static func liteLLM(_ data: Data, at now: Date) throws -> PricingTable {
        let json = try JSON.parse(data)
        guard let entries = json.object else { throw ProviderError.malformedResponse("price list") }
        var models: [String: ModelPrice] = [:]
        for (name, entry) in entries {
            guard let provider = entry["litellm_provider"].string, providers.contains(provider),
                  let input = entry["input_cost_per_token"].double,
                  let output = entry["output_cost_per_token"].double else { continue }
            let key = name.hasPrefix("xai/") ? String(name.dropFirst(4)) : name
            models[key] = ModelPrice(
                input: input, output: output,
                cacheWrite: entry["cache_creation_input_token_cost"].double ?? 0,
                cacheRead: entry["cache_read_input_token_cost"].double ?? 0
            )
        }
        return PricingTable(updated: now, models: models)
    }

    /// models.dev: provider → models → `cost` in USD per million tokens.
    public static func modelsDev(_ data: Data, at now: Date) throws -> PricingTable {
        let json = try JSON.parse(data)
        var models: [String: ModelPrice] = [:]
        for provider in providers {
            guard let entries = json[provider]["models"].object else { continue }
            for (name, entry) in entries {
                let cost = entry["cost"]
                guard let input = cost["input"].double, let output = cost["output"].double else { continue }
                models[name] = ModelPrice(
                    input: input / 1_000_000, output: output / 1_000_000,
                    cacheWrite: (cost["cache_write"].double ?? 0) / 1_000_000,
                    cacheRead: (cost["cache_read"].double ?? 0) / 1_000_000
                )
            }
        }
        guard !models.isEmpty else { throw ProviderError.malformedResponse("price list") }
        return PricingTable(updated: now, models: models)
    }

    /// OpenUsage's supplement: prices for models the public catalogs lack (Cursor's `auto`,
    /// `composer-*`), regex alias rules for vendor slugs, and `-fast` multipliers. Per million.
    public static let supplementURL = URL(string: "https://robinebers.github.io/openusage/pricing_supplement.json")!

    public static func supplement(_ data: Data, at now: Date?) throws -> PricingTable {
        let json = try JSON.parse(data)
        guard let pricing = json["pricing"].object else { throw ProviderError.malformedResponse("pricing supplement") }
        var models: [String: ModelPrice] = [:]
        for (name, entry) in pricing {
            guard let input = entry["input_per_million"].double, let output = entry["output_per_million"].double else { continue }
            models[name] = ModelPrice(
                input: input / 1_000_000, output: output / 1_000_000,
                cacheWrite: (entry["cache_write_per_million"].double ?? input) / 1_000_000,
                cacheRead: (entry["cache_read_per_million"].double ?? input * 0.1) / 1_000_000
            )
        }
        let aliases = (json["alias_rules"].array ?? []).compactMap { rule -> AliasRule? in
            guard let pattern = rule["pattern"].string, let canonical = rule["canonical"].string else { return nil }
            return AliasRule(pattern: pattern, canonical: canonical)
        }
        let fast = (json["fast_multipliers"].object ?? [:]).compactMapValues(\.double)
        return PricingTable(updated: now, models: models, aliases: aliases, fastMultipliers: fast)
    }
}

/// Holds the effective price table: bundled snapshot, overlaid with the last successful fetch,
/// refreshed at most hourly. Fetch failures keep whatever we had.
public actor PricingStore {
    private let environment: HostEnvironment
    private let bundled: PricingTable
    private var fetched: PricingTable?
    private var lastAttempt: Date?
    public static let refreshInterval: TimeInterval = 3600

    public init(environment: HostEnvironment, bundled: PricingTable = .bundled()) {
        self.environment = environment
        self.bundled = bundled
        if let data = try? environment.readFile(environment.dataDirectory.appending(path: "pricing-cache.json")),
           let cached = try? JSONDecoder.pricing.decode(PricingTable.self, from: data) {
            fetched = cached
        }
    }

    public var current: PricingTable {
        fetched.map { bundled.merging($0) } ?? bundled
    }

    /// Fetches LiteLLM, overlays models.dev for models LiteLLM lacks, then the supplement on top.
    @discardableResult
    public func refreshIfNeeded() async -> PricingTable {
        let now = environment.now()
        if let last = lastAttempt, now.timeIntervalSince(last) < Self.refreshInterval { return current }
        lastAttempt = now

        var table: PricingTable?
        if let r = try? await environment.send(HTTPRequest(url: PricingSource.liteLLMURL)), r.isSuccess,
           let t = try? PricingSource.liteLLM(r.body, at: now) {
            table = t
        }
        if let r = try? await environment.send(HTTPRequest(url: PricingSource.modelsDevURL)), r.isSuccess,
           let t = try? PricingSource.modelsDev(r.body, at: now) {
            // LiteLLM entries win where both know a model.
            table = table.map { t.merging($0) } ?? t
        }
        if let r = try? await environment.send(HTTPRequest(url: PricingSource.supplementURL)), r.isSuccess,
           let t = try? PricingSource.supplement(r.body, at: now) {
            table = table.map { $0.merging(t) } ?? t
        }
        if let table {
            fetched = table
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(table) {
                try? environment.writeFile(environment.dataDirectory.appending(path: "pricing-cache.json"), data)
            }
        }
        return current
    }
}
