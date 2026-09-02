import Foundation

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

public struct PricingTable: Sendable, Equatable, Codable {
    public var updated: Date?
    public var models: [String: ModelPrice]

    public init(updated: Date? = nil, models: [String: ModelPrice]) {
        self.updated = updated
        self.models = models
    }

    /// Exact match first, then progressively looser forms: provider prefix stripped, date
    /// suffix stripped, `-latest` stripped.
    public func price(for model: String) -> ModelPrice? {
        for candidate in Self.candidates(for: model) {
            if let p = models[candidate] { return p }
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

    /// Entries in `other` win.
    public func merging(_ other: PricingTable) -> PricingTable {
        PricingTable(updated: other.updated ?? updated, models: models.merging(other.models) { $1 })
    }

    /// The snapshot compiled into the app, for first launch and offline use.
    public static func bundled() -> PricingTable {
        guard let url = Bundle.module.url(forResource: "pricing", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder.pricing.decode(PricingTable.self, from: data) else {
            return PricingTable(models: [:])
        }
        return table
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

    /// Fetches LiteLLM, then overlays models.dev for models LiteLLM lacks.
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
