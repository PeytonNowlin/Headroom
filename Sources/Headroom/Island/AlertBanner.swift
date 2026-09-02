import HeadroomCore
import SwiftUI

/// Glass banner that drops from under the island when a quota crosses a threshold.
struct AlertBanner: View {
    let alert: UsageAlert
    @Environment(\.colorScheme) private var scheme

    private var color: Color {
        switch alert.kind {
        case .threshold(95): Urgency.critical.color(for: scheme)
        case .threshold: Urgency.warn.color(for: scheme)
        case .paceExhaustion: Urgency.watch.color(for: scheme)
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            ProviderGlyph(provider: alert.provider, size: 12)
                .foregroundStyle(color)
            Text(alert.message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
        .accessibilityLabel(alert.message)
    }
}
