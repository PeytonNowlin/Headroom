import HeadroomCore
import SwiftUI

/// One provider's gauge: a draining ring colored by urgency, a glyph in the well, and the
/// percent-remaining label. Handles loading, expired, and stale presentations.
struct RingView: View {
    let provider: ProviderID
    let state: ProviderState?
    let status: ConnectionStatus
    var diameter: CGFloat = 48
    var lineWidth: CGFloat = 3.5

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var spin = false

    private var snapshot: Snapshot? { state?.snapshot }
    private var usedPercent: Double? { snapshot?.ringUsedPercent }
    private var remaining: Double? { snapshot?.ringRemainingPercent }
    private var urgency: Urgency? { usedPercent.map(Urgency.init(usedPercent:)) }
    private var isErrored: Bool { state?.isErrored == true }
    private var isLoading: Bool { snapshot == nil && !isErrored }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.10), lineWidth: lineWidth)

                if status == .expired {
                    Circle()
                        .stroke(.secondary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [4, 5]))
                } else if isErrored {
                    Circle()
                        .stroke(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [1.5, 4]))
                } else if isLoading {
                    Circle()
                        .trim(from: 0, to: 0.23)
                        .stroke(.secondary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .task(id: reduceMotion) {
                            spin = false
                            guard !reduceMotion else { return }
                            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
                        }
                } else if let remaining, let urgency {
                    Circle()
                        .trim(from: 0, to: max(0.004, remaining / 100))
                        .stroke(urgency.color(for: scheme), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(urgency.pulses && pulse ? 0.4 : 1)
                        .animation(Motion.ringSweep, value: remaining)
                        .task(id: urgency.pulses && !reduceMotion) {
                            pulse = false
                            if urgency.pulses && !reduceMotion {
                                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulse = true }
                            }
                        }
                }

                well
            }
            .frame(width: diameter, height: diameter)

            Text(label)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(status == .expired ? .secondary : .primary)
                .monospacedDigit()
        }
        .opacity(status == .stale ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.displayName)
        .accessibilityValue(accessibilityStatus)
    }

    private var accessibilityStatus: String {
        if status == .expired { return "Login expired" }
        if isErrored { return "Provider unavailable" }
        if isLoading { return "Checking usage" }
        guard let remaining else { return "Quota unavailable" }
        let saved = status == .stale || state?.lastError != nil ? ", showing saved usage" : ""
        return "\(Int(remaining.rounded())) percent remaining\(saved)"
    }

    private var well: some View {
        ZStack {
            Circle()
                .fill(.primary.opacity(0.08))
                .overlay(
                    Circle()
                        .trim(from: 0.55, to: 0.95)
                        .stroke(.white.opacity(0.35), lineWidth: 0.6)
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 0.3)
                )
            ProviderGlyph(provider: provider, size: diameter * 0.36)
                .foregroundStyle(status == .expired ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .frame(width: diameter - lineWidth * 2 - 8, height: diameter - lineWidth * 2 - 8)
    }

    private var label: String {
        switch status {
        case .expired: return "—"
        case .absent: return isErrored ? "!" : (isLoading ? "…" : "—")
        case .connected, .stale:
            guard let remaining else { return isLoading ? "…" : "—" }
            return "\(Int(remaining.rounded()))%"
        }
    }
}

/// Remaining quota in a tiny ring, with a single pulse after confirmed recovery.
struct ProviderDot: View {
    let state: ProviderState?
    let status: ConnectionStatus
    @Environment(\.colorScheme) private var scheme

    var resetAt: Date? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = Self.color(state: state, status: status, scheme: scheme) ?? .clear
        let remaining = min(1, max(0, (state?.snapshot?.ringRemainingPercent ?? 0) / 100))
        ZStack {
            Circle().strokeBorder(color.opacity(0.28), lineWidth: 1.5)
            if status == .expired || state?.lastError != nil {
                Text("!").font(.system(size: 7, weight: .heavy)).foregroundStyle(color)
            } else {
                Circle().trim(from: 0, to: remaining)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(0.9)
            }
        }
        .frame(width: 9, height: 9)
        .phaseAnimator([false, true, false], trigger: resetAt) { content, active in
            content.scaleEffect(active && !reduceMotion ? 1.3 : 1)
                .brightness(active && !reduceMotion ? 0.2 : 0)
        } animation: { _ in .easeInOut(duration: 0.25) }
        .accessibilityElement(children: .ignore)
        .opacity(status == .stale ? 0.6 : 1)
    }

    /// Nil means "no dot": there is no quota to summarize (e.g. a Grok Business login, which
    /// publishes no personal limits) or no credentials at all.
    static func color(state: ProviderState?, status: ConnectionStatus, scheme: ColorScheme) -> Color? {
        switch status {
        case .expired:
            return .secondary.opacity(0.6)
        case .absent:
            return state?.isErrored == true ? .secondary.opacity(0.4) : nil
        case .connected, .stale:
            guard let used = state?.snapshot?.ringUsedPercent else { return nil }
            return Urgency(usedPercent: used).color(for: scheme)
        }
    }

    static func shows(state: ProviderState?, status: ConnectionStatus) -> Bool {
        color(state: state, status: status, scheme: .dark) != nil
    }
}
