import HeadroomCore
import SwiftUI

/// Three tiles: Today, Yesterday, Last 30 Days.
struct SpendTiles: View {
    let summary: SpendSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Estimated token value")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SpendTileView(title: "Today", tile: summary.today)
                SpendTileView(title: "Yesterday", tile: summary.yesterday)
                SpendTileView(title: "30 Days", tile: summary.last30Days)
            }
            Text("Usage valued from token prices or recorded costs; not your subscription bill.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if summary.last30Days.unpricedTokens > 0 {
                Text("* Partial estimate · \(Formatting.tokens(summary.last30Days.unpricedTokens)) tokens have no known price.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SpendTileView: View {
    let title: String
    let tile: SpendTile

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            if tile.hasData {
                Text(Formatting.dollars(tile.cost) + (tile.unpricedTokens > 0 ? "*" : ""))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(Formatting.tokens(tile.tokens)) tok")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else {
                Text("No data")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .help(tile.unpricedTokens > 0 ? "Some tokens used a model with no known price" : "")
    }
}

/// One-line cross-provider total under the ring row.
struct SpendFooter: View {
    let summary: SpendSummary

    var body: some View {
        VStack(spacing: 4) {
            Text(summary.last30Days.unpricedTokens > 0 ? "Estimated token value · * incomplete pricing" : "Estimated token value")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                item("Today", summary.today)
                divider
                item("Yesterday", summary.yesterday)
                divider
                item("30d", summary.last30Days)
            }
        }
        .help("Token value uses model prices or recorded costs, not your subscription bill. An asterisk means some tokens have no known price and are excluded.")
        .font(.system(size: 11, design: .rounded))
        .monospacedDigit()
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.15)).frame(width: 1, height: 20)
    }

    private func item(_ label: String, _ tile: SpendTile) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Text(label).foregroundStyle(.tertiary)
                Text(tile.hasData ? Formatting.dollars(tile.cost) + (tile.unpricedTokens > 0 ? "*" : "") : "—")
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Text(tile.hasData ? "\(Formatting.tokens(tile.tokens)) tok" : " ")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
    }
}
