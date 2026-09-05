import Foundation

public enum SpendPeriod: Int, CaseIterable, Sendable, Identifiable {
    case week = 7
    case month = 30
    public var id: Int { rawValue }
    public var title: String { "\(rawValue) days" }
}

/// Daily and per-model views of the same estimated token value used in the island.
public struct SpendTrend: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public var date: Date
        public var tile: SpendTile
        public var id: Date { date }
    }

    public struct Model: Equatable, Sendable, Identifiable {
        public var name: String
        public var tile: SpendTile
        public var id: String { name }
    }

    public var days: [Day]
    public var models: [Model]
    public var total: SpendTile { days.reduce(.empty) { $0 + $1.tile } }

    public static func make(_ ledger: SpendLedger, pricing: PricingTable, now: Date,
                            calendar: Calendar, period: SpendPeriod) -> SpendTrend {
        let today = calendar.startOfDay(for: now)
        var models: [String: SpendTile] = [:]
        let days = (0..<period.rawValue).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let entries = ledger.days[SpendLedger.dayKey(date, calendar: calendar)] ?? [:]
            for (name, day) in entries {
                models[name, default: .empty] = models[name, default: .empty] + SpendSummarizer.tile([name: day], pricing: pricing)
            }
            return Day(date: date, tile: SpendSummarizer.tile(entries, pricing: pricing))
        }
        return SpendTrend(days: days, models: sorted(models))
    }

    public static func combine(_ trends: [SpendTrend]) -> SpendTrend? {
        guard !trends.isEmpty else { return nil }
        var days: [Date: SpendTile] = [:]
        var models: [String: SpendTile] = [:]
        for trend in trends {
            for day in trend.days { days[day.date, default: .empty] = days[day.date, default: .empty] + day.tile }
            for model in trend.models { models[model.name, default: .empty] = models[model.name, default: .empty] + model.tile }
        }
        return SpendTrend(days: days.keys.sorted().map { Day(date: $0, tile: days[$0]!) }, models: sorted(models))
    }

    private static func sorted(_ models: [String: SpendTile]) -> [Model] {
        models.map { Model(name: $0.key, tile: $0.value) }.sorted {
            if $0.tile.cost != $1.tile.cost { return $0.tile.cost > $1.tile.cost }
            return $0.name < $1.name
        }
    }
}
