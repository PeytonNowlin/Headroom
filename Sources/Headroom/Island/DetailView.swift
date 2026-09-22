import HeadroomCore
import SwiftUI

/// One provider’s quotas, connection actions, and forecasts.
struct DetailView: View {
    let provider: ProviderID
    let state: ProviderState?
    let status: ConnectionStatus
    let now: Date
    var model: UsageModel
    let onBack: () -> Void
    @FocusState private var backFocused: Bool

    private var snapshot: Snapshot? { state?.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ConnectionView(provider: provider, state: state, now: now) { model.refresh(provider) }
            switch status {
            case .expired, .absent:
                EmptyView()
            case .connected, .stale:
                if let snapshot {
                    VStack(spacing: 8) {
                        ForEach(snapshot.windows) { window in
                            WindowRow(window: window, now: now, forecast: model.forecast(window, provider: provider))
                        }
                    }
                    if let note = snapshot.note {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let extra = snapshot.extraUsage {
                        LabeledRow(title: "Extra usage", value: Formatting.extraUsage(extra))
                    }
                    if let credits = snapshot.resetCredits {
                        LabeledRow(title: "Early resets", value: credits == 1 ? "1 left" : "\(credits) left")
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            // The one alert control anywhere: silence this provider until its quota comes back.
            if snapshot?.windows.contains(where: { ($0.resetsAt.map { $0 > now } ?? false) }) == true {
                Button(model.alertsSnoozed(provider) ? "Warn me again" : "Quiet until reset") {
                    toggleWarnings()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .focusable()
                .onKeyPress(keys: [.return, .space], phases: .down) { _ in toggleWarnings(); return .handled }
                .accessibilityLabel(model.alertsSnoozed(provider) ? "Warn me again" : "Quiet until reset")
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .onAppear { backFocused = true }
    }

    private func toggleWarnings() {
        if model.alertsSnoozed(provider) { model.resumeAlerts(provider) }
        else { model.snoozeAlerts(provider) }
    }

    private var header: some View {
        Button(action: onBack) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ProviderGlyph(provider: provider, size: 14)
                Text(provider.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if let plan = snapshot?.planName {
                    Text(plan)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.1), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(refreshLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .onKeyPress(keys: [.return, .space], phases: .down) { _ in onBack(); return .handled }
        .accessibilityLabel("Back to all providers")
        .focused($backFocused)
    }

    private var refreshLine: String {
        var parts: [String] = []
        if state?.isRefreshing == true {
            parts.append("checking")
        } else if let next = state?.nextRefreshAt {
            let label = state?.isRateLimited(at: now) == true ? "waiting" : "next"
            parts.append("\(label) \(Formatting.clock(to: next, from: now))")
        }
        return parts.joined(separator: " · ")
    }
}

/// A quota window: title, draining capsule bar, percent left, and reset countdown.
struct WindowRow: View {
    let window: QuotaWindow
    let now: Date
    var forecast: Pace.Forecast?
    @Environment(\.colorScheme) private var scheme

    private var urgency: Urgency { Urgency(usedPercent: window.usedPercent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))% left")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(urgency.color(for: scheme))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.10))
                    Capsule()
                        .fill(urgency.color(for: scheme))
                        .frame(width: max(5, geo.size.width * window.remainingPercent / 100))
                        .animation(Motion.ringSweep, value: window.remainingPercent)
                }
            }
            .frame(height: 5)
            Text(resetText)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            // One line of estimate at most. Bursty usage and thin data both say nothing rather
            // than explain themselves.
            if window.remainingPercent == 0 {
                Text("Out until reset")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else if let forecast, !forecast.isVariable {
                Text("At this rate · \(Pace.hint(forecast.recent, now: now))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(paceIsBad(forecast.recent) ? urgencyWarn : .secondary)
            }
        }
    }

    private var urgencyWarn: Color { Urgency.warn.color(for: scheme) }

    private func paceIsBad(_ p: Pace.Projection) -> Bool {
        if case .runsOut = p { return true }
        return false
    }

    private var resetText: String {
        guard window.isStarted else { return "Starts with your first message" }
        guard let resets = window.resetsAt else { return "" }
        return resets > now ? "Back in \(Formatting.countdown(to: resets, from: now))" : "Resetting"
    }
}

struct LabeledRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}
