import HeadroomCore
import SwiftUI

/// One provider's drill-in: header, a row per quota window, extra usage, and (later) spend.
struct DetailView: View {
    let provider: ProviderID
    let state: ProviderState?
    let status: ConnectionStatus
    let now: Date
    let onBack: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var snapshot: Snapshot? { state?.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch status {
            case .expired:
                reconnect
            case .absent:
                Text("Not signed in")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .connected, .stale:
                if let snapshot {
                    VStack(spacing: 8) {
                        ForEach(snapshot.windows) { window in
                            WindowRow(window: window, now: now)
                        }
                    }
                    if let extra = snapshot.extraUsage {
                        LabeledRow(title: "Extra Usage", value: Formatting.extraUsage(extra))
                    }
                    if let credits = snapshot.resetCredits {
                        LabeledRow(title: "Rate Limit Resets", value: credits == 1 ? "1 available" : "\(credits) available")
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .opacity(status == .stale ? 0.7 : 1)
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
                if status == .stale, let fetched = snapshot?.fetchedAt {
                    Text("updated \(Formatting.countdown(to: now, from: fetched)) ago")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reconnect: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
            Text("Login expired — run `\(provider.signInCommand)` to reconnect")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

/// A quota window: title, draining capsule bar, percent left, and reset countdown.
struct WindowRow: View {
    let window: QuotaWindow
    let now: Date
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
        }
    }

    private var resetText: String {
        guard window.isStarted else { return "Not started — begins with your first message" }
        guard let resets = window.resetsAt else { return "" }
        return "Resets in \(Formatting.countdown(to: resets, from: now))"
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
