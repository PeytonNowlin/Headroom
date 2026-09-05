import AppKit
import HeadroomCore
import SwiftUI
import Testing
@testable import Headroom

/// Opt-in native layout captures. AppKit's cacheDisplay cannot reproduce the desktop glass
/// backdrop. No live credentials, network, or production preferences are used.
@Suite("Island rendering", .serialized)
@MainActor
struct IslandRenderingTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HEADROOM_UI_ARTIFACTS"] != nil))
    func captureRepresentativeStates() async throws {
        _ = NSApplication.shared
        let directory = URL(filePath: try #require(ProcessInfo.processInfo.environment["HEADROOM_UI_ARTIFACTS"]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "HeadroomRenderingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let now = Date()
        let windows = [
            QuotaWindow(id: "session", title: "Session", usedPercent: 76, resetsAt: now.addingTimeInterval(7200), duration: 18000),
            QuotaWindow(id: "weekly", title: "Weekly · premium models", usedPercent: 92, resetsAt: now.addingTimeInterval(3 * 86400), duration: 7 * 86400),
        ]
        let snapshots = ProviderID.allCases.map { provider in
            Snapshot(provider: provider, fetchedAt: now.addingTimeInterval(-1080), status: .connected,
                     planName: "Pro", windows: windows)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let saved = try encoder.encode(Dictionary(uniqueKeysWithValues: snapshots.map {
            ($0.provider.rawValue, SnapshotStore.Entry(snapshot: $0))
        }))
        let environment = HostEnvironment(
            home: URL(filePath: "/tmp/headroom-rendering"), timeZone: .gmt,
            readFile: { url in url.lastPathComponent == "snapshots.json" ? saved : Data() },
            fileExists: { _ in false }, keychainPassword: { _ in nil }, environmentVariable: { _ in nil },
            send: { _ in throw ProviderError.transient(statusCode: nil) }, now: { now },
            sleep: { try await Task.sleep(for: $0) }
        )
        let model = UsageModel(environment: environment, preferences: preferences)
        let layout = IslandLayout.make(for: .simulatedNotch(height: 32))
        let state = IslandState(layout: layout)
        state.mode = .expanded
        try await capture(IslandView(state: state, model: model), size: layout.panel,
                          name: "expanded-saved", directory: directory)
        state.mode = .compact
        try await capture(IslandView(state: state, model: model), size: CGSize(width: layout.panel.width, height: 80),
                          name: "compact", directory: directory)
        state.hoveredProvider = .codex
        try await capture(IslandView(state: state, model: model), size: layout.panel,
                          name: "compact-led-hover", directory: directory)
        state.hoveredProvider = nil
        try await capture(HStack(spacing: 20) {
            ForEach([0.0, 25, 50, 75, 95, 100], id: \.self) { used in
                VStack {
                    ProviderDot(state: ProviderState(provider: .claude, snapshot: Snapshot(provider: .claude, fetchedAt: now, status: .connected,
                        windows: [QuotaWindow(id: "session", title: "Session", usedPercent: used, resetsAt: now.addingTimeInterval(3600), duration: 18000)])), status: .connected)
                    Text("\(Int(100 - used))%").font(.caption)
                }
            }
        }.padding(20).background(.black).environment(\.colorScheme, .dark), size: CGSize(width: 420, height: 90),
                          name: "led-gauges", directory: directory)
        state.mode = .detail(.claude)
        try await capture(IslandView(state: state, model: model), size: layout.panel,
                          name: "detail-saved", directory: directory)
        #expect(state.currentSize.height <= IslandLayout.maxHeight - 110)

        let partial = SpendTile(cost: 12.34, tokens: 500_000, calls: 100, hasData: true, unpricedTokens: 12_000)
        let summary = SpendSummary(today: partial, yesterday: .empty, last30Days: partial, dailyCost: [], computedAt: now)
        try await capture(VStack(spacing: 24) {
            SpendTiles(summary: summary)
            SpendFooter(summary: summary)
        }.padding(20), size: CGSize(width: 440, height: 260), name: "partial-token-value", directory: directory)

        try await capture(VStack(alignment: .leading, spacing: 18) {
            ConnectionView(provider: .claude, state: ProviderState(provider: .claude), now: now) {}
            ConnectionView(provider: .codex, state: ProviderState(provider: .codex, snapshot: .expired(.codex, at: now)), now: now) {}
            ConnectionView(provider: .grok, state: ProviderState(provider: .grok, lastError: "Network unavailable"), now: now) {}
            ConnectionView(provider: .cursor, state: ProviderState(provider: .cursor, lastError: "Rate limited", rateLimitedUntil: now.addingTimeInterval(240)), now: now) {}
        }.padding(20), size: CGSize(width: 440, height: 380), name: "connection-recovery", directory: directory)

        try await capture(SettingsView(model: model, preferences: preferences), size: CGSize(width: 520, height: 720),
                          name: "settings", directory: directory)
        try await capture(SettingsView(model: model, preferences: preferences), size: CGSize(width: 520, height: 1600),
                          name: "settings-full", directory: directory)
        try await capture(TrendsView(model: model), size: CGSize(width: 680, height: 680),
                          name: "trends-empty", directory: directory)
        let trendModel = UsageModel(environment: SpendModelFixture().environment, preferences: preferences)
        await trendModel.rescanSpend(force: true)
        try await capture(TrendsView(model: trendModel), size: CGSize(width: 680, height: 760),
                          name: "trends-populated", directory: directory)
        let quota = windows[0]
        var history = UsageHistory()
        for (ago, used) in [(600.0, 66.0), (300.0, 71.0), (0.0, 76.0)] {
            var sample = snapshots[0]
            sample.fetchedAt = now.addingTimeInterval(-ago)
            sample.windows = [QuotaWindow(id: quota.id, title: quota.title, usedPercent: used, resetsAt: quota.resetsAt, duration: quota.duration)]
            history.record(sample)
        }
        let forecast = try #require(Pace.forecast(quota, provider: .claude, history: history, now: now))
        try await capture(WindowRow(window: quota, now: now, forecast: forecast).padding(20),
                          size: CGSize(width: 440, height: 180), name: "forecast", directory: directory)
        var ledger = AlertLedger()
        var highUsage = snapshots[0]
        highUsage.fetchedAt = now
        highUsage.windows = [QuotaWindow(id: quota.id, title: quota.title, usedPercent: 96, resetsAt: quota.resetsAt, duration: quota.duration)]
        let alert = try #require(AlertEvaluator.evaluate(highUsage, now: now, ledger: &ledger, forecasts: [quota.id: forecast]).first)
        try await capture(AlertBanner(alert: alert), size: CGSize(width: 440, height: 110), name: "combined-alert", directory: directory)
    }

    private func capture<V: View>(_ view: V, size: CGSize, name: String, directory: URL) async throws {
        let root = view.environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.85, green: 0.9, blue: 0.94))
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.9, blue: 0.94, alpha: 1)
        window.contentView = host
        window.setContentSize(size)
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        try png.write(to: directory.appending(path: name + ".png"))
        #expect(host.bounds.width == size.width)
    }
}
