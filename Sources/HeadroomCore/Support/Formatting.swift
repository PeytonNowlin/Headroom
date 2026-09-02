import Foundation

public enum Formatting {
    /// Compact countdown: `3h 12m`, `2d 5h`, `45s`, or `now` once passed.
    public static func countdown(to target: Date, from now: Date) -> String {
        let seconds = Int(target.timeIntervalSince(now).rounded(.down))
        guard seconds > 0 else { return "now" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    /// `4:07` / `0:09` style clock for short waits; falls back to `countdown` past an hour.
    public static func clock(to target: Date, from now: Date) -> String {
        let seconds = Int(target.timeIntervalSince(now).rounded(.down))
        guard seconds > 0 else { return "0:00" }
        guard seconds < 3600 else { return countdown(to: target, from: now) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// `$4.08`, `$0.50`, `$1,234.00`.
    public static func dollars(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    /// `1.2B`, `845M`, `1.2M`, `845K`, `312`.
    public static func tokens(_ count: Int) -> String {
        switch count {
        case 1_000_000_000...:
            return trim(Double(count) / 1_000_000_000) + "B"
        case 1_000_000...:
            return trim(Double(count) / 1_000_000) + "M"
        case 1_000...:
            return trim(Double(count) / 1_000) + "K"
        default:
            return String(count)
        }
    }

    private static func trim(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    /// Extra-usage row text.
    public static func extraUsage(_ extra: ExtraUsage) -> String {
        if let label = extra.label { return label }
        guard extra.isEnabled else { return "Disabled" }
        switch (extra.usedDollars, extra.limitDollars) {
        case let (used?, limit?) where limit > 0:
            return "\(dollars(used)) of \(dollars(limit))"
        case let (used?, _):
            return "\(dollars(used)) used"
        default:
            return "Enabled"
        }
    }
}
