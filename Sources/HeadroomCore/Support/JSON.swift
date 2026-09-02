import Foundation

/// A tolerant JSON value for provider payloads whose schemas drift and contain many nullable
/// experimental fields. Mappers pull what they need and ignore the rest.
public enum JSON: Sendable, Equatable {
    case object([String: JSON])
    case array([JSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public static func parse(_ data: Data) throws -> JSON {
        let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return JSON(any: raw)
    }

    init(any: Any) {
        switch any {
        case let dict as [String: Any]:
            self = .object(dict.mapValues(JSON.init(any:)))
        case let arr as [Any]:
            self = .array(arr.map(JSON.init(any:)))
        case let s as String:
            self = .string(s)
        case let n as NSNumber:
            // JSONSerialization emits CFBoolean for true/false and NSNumber for numerics, but
            // `as? Bool` also succeeds for 0 and 1, so discriminate on the CF type instead.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .number(n.doubleValue)
            }
        case is NSNull:
            self = .null
        default:
            self = .null
        }
    }

    public subscript(key: String) -> JSON {
        if case let .object(o) = self { return o[key] ?? .null }
        return .null
    }

    public subscript(index: Int) -> JSON {
        if case let .array(a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    public var string: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    public var double: Double? {
        switch self {
        case let .number(n): return n
        case let .string(s): return Double(s)
        default: return nil
        }
    }

    public var int: Int? { double.map { Int($0) } }

    public var bool: Bool? {
        if case let .bool(b) = self { return b }
        return nil
    }

    public var array: [JSON]? {
        if case let .array(a) = self { return a }
        return nil
    }

    public var object: [String: JSON]? {
        if case let .object(o) = self { return o }
        return nil
    }

    public var isNull: Bool { self == .null }

    /// ISO-8601 with or without fractional seconds.
    public var isoDate: Date? {
        guard let s = string else { return nil }
        return DateParsing.iso8601(s)
    }

    /// Unix epoch seconds (or milliseconds when the magnitude says so).
    public var epochDate: Date? {
        guard let n = double else { return nil }
        return n > 1_000_000_000_000 ? Date(timeIntervalSince1970: n / 1000) : Date(timeIntervalSince1970: n)
    }
}

public enum DateParsing {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func iso8601(_ s: String) -> Date? {
        fractional.date(from: s) ?? plain.date(from: s)
    }
}
