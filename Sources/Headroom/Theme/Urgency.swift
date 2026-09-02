import SwiftUI

/// The four-step urgency scale, keyed on percent *used*. Ported from Tokenly.
enum Urgency: Equatable {
    case fine
    case watch
    case warn
    case critical

    init(usedPercent: Double) {
        switch usedPercent {
        case ..<40: self = .fine
        case ..<70: self = .watch
        case ..<90: self = .warn
        default: self = .critical
        }
    }

    func color(for scheme: ColorScheme) -> Color {
        switch self {
        case .fine: Color(hex: 0x32D74B)
        case .watch: scheme == .dark ? Color(hex: 0xE4FF1A) : Color(hex: 0xB8A400)
        case .warn: Color(hex: 0xFF4F1F)
        case .critical: Color(hex: 0xFF3B30)
        }
    }

    var pulses: Bool { self == .critical }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
