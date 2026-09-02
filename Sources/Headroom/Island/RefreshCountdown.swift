import HeadroomCore
import SwiftUI

/// "↻ 4:07" — time until the soonest provider refresh; spins while any refresh is in flight.
struct RefreshCountdown: View {
    var model: UsageModel
    @State private var spin = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .font(.system(size: 8, weight: .semibold))
                .rotationEffect(.degrees(spin ? 360 : 0))
            if model.isAnyRefreshing {
                Text("refreshing")
            } else if let next = model.nextRefreshAt {
                Text(Formatting.clock(to: next, from: model.now))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
        }
        .font(.system(size: 9.5, weight: .medium, design: .rounded))
        .foregroundStyle(.tertiary)
        .onChange(of: model.isAnyRefreshing, initial: true) { _, refreshing in
            if refreshing {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
            } else {
                withAnimation(.default) { spin = false }
            }
        }
        .help("Next automatic refresh. Right-click → Refresh Now to fetch sooner.")
    }
}
