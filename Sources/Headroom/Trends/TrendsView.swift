import Charts
import HeadroomCore
import SwiftUI

struct TrendsView: View {
    var model: UsageModel
    @State var provider: ProviderID?
    @State private var period: SpendPeriod = .week

    private var trend: SpendTrend? { model.trend(provider: provider, period: period) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Usage trends").font(.title2.bold())
                        Text("Estimated token value · not your subscription bill")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") { model.refreshAll() }
                }
                HStack {
                    Picker("Provider", selection: $provider) {
                        Text("All providers").tag(ProviderID?.none)
                        ForEach(ProviderID.allCases) { Text($0.displayName).tag(Optional($0)) }
                    }
                    .frame(width: 210)
                    Spacer()
                    Picker("Period", selection: $period) {
                        ForEach(SpendPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                if let trend, trend.total.hasData {
                    HStack(spacing: 24) {
                        metric("Estimated value", Formatting.dollars(trend.total.cost) + (trend.total.unpricedTokens > 0 ? "*" : ""))
                        metric("Tokens", Formatting.tokens(trend.total.tokens))
                        metric("Recorded calls", trend.total.calls.formatted())
                    }
                    Chart(trend.days) { day in
                        if day.tile.hasData {
                            BarMark(x: .value("Day", dayLabel(day.date)), y: .value("Estimated value", day.tile.cost))
                                .foregroundStyle(Color.accentColor.gradient)
                                .accessibilityLabel(dayLabel(day.date))
                                .accessibilityValue(Formatting.dollars(day.tile.cost) + (day.tile.unpricedTokens > 0 ? ", incomplete pricing" : ""))
                        }
                    }
                    .chartXScale(domain: trend.days.map { dayLabel($0.date) })
                    .chartXAxis {
                        AxisMarks(values: trend.days.enumerated().compactMap { index, day in
                            index % (period == .week ? 1 : 5) == 0 ? dayLabel(day.date) : nil
                        }) { AxisValueLabel() }
                    }
                    .chartYAxis { AxisMarks(format: Decimal.FormatStyle.Currency(code: "USD")) }
                    .frame(height: 200)
                    Text("Days without records are gaps, not confirmed zero usage. Values use current token prices or recorded costs.")
                        .font(.caption).foregroundStyle(.secondary)
                    if trend.total.unpricedTokens > 0 {
                        Text("* Partial estimate: \(Formatting.tokens(trend.total.unpricedTokens)) tokens have no known price and are excluded from the dollar total.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Text("By model").font(.headline)
                    ForEach(trend.models) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.name).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                Spacer()
                                Text(Formatting.dollars(entry.tile.cost) + (entry.tile.unpricedTokens > 0 ? "*" : ""))
                                    .monospacedDigit()
                            }
                            ProgressView(value: entry.tile.cost, total: max(0.000001, trend.total.cost))
                                .accessibilityHidden(true)
                            Text("\(Formatting.tokens(entry.tile.tokens)) tokens · \(entry.tile.calls.formatted()) recorded calls")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    DisclosureGroup("Daily values") {
                        ForEach(trend.days.reversed()) { day in
                            HStack {
                                Text(day.date, format: .dateTime.month(.abbreviated).day())
                                Spacer()
                                Text(day.tile.hasData ? Formatting.dollars(day.tile.cost) + (day.tile.unpricedTokens > 0 ? "*" : "") : "No records")
                            }
                            .font(.callout)
                            .accessibilityElement(children: .combine)
                        }
                    }
                } else {
                    ContentUnavailableView("No usage records", systemImage: "chart.bar", description: Text("Recorded activity for this provider and period will appear here after the next local scan."))
                }
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 520)
        .environment(\.calendar, model.environment.calendar)
        .environment(\.timeZone, model.environment.timeZone)
    }

    private func dayLabel(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.calendar = model.environment.calendar
        style.timeZone = model.environment.timeZone
        return date.formatted(style)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
