import HeadroomCore
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var model: UsageModel
    @Bindable var preferences: Preferences
    var updater: UpdateController?
    var notifications: NotificationController?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                providers
                connections
                alerts
                behavior
                updates
                about
            }
            .padding(22)
        }
        .frame(width: 520)
        .frame(minHeight: 480, idealHeight: 560)
        .background(.regularMaterial)
    }

    // MARK: - Providers

    private var providers: some View {
        Section("Providers", footnote: "Main agents decide whether the island appears at all — when they have room, nothing is drawn. Side providers ride along once it is up. Drag to reorder.") {
            List {
                ForEach(preferences.order) { id in
                    ProviderRow(id: id, model: model, preferences: preferences)
                }
                .onMove { preferences.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(height: CGFloat(preferences.order.count) * 44 + 4)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var connections: some View {
        Section("Connections", footnote: "Headroom only reads your existing logins. Sign in using the provider, then check again here.") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(preferences.order) { id in
                    VStack(alignment: .leading, spacing: 5) {
                        Label { Text(id.displayName).fontWeight(.medium) } icon: {
                            ProviderGlyph(provider: id, size: 12)
                        }
                        ConnectionView(provider: id, state: model.state(id), now: model.now) { model.refresh(id) }
                    }
                }
            }
            .padding(12)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// One switch. Warnings themselves are not configurable: they fire near the edge, once per
    /// window, and each provider's drill-in can quiet it until that quota comes back.
    @ViewBuilder
    private var alerts: some View {
        if let notifications {
            Section("Alerts", footnote: "Warnings appear in the island near the edge of a quota window. Turn this on to get them as macOS notifications too.") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Send macOS notifications", isOn: Binding(
                        get: { notifications.enabled },
                        set: { enabled in Task { await notifications.setEnabled(enabled) } }
                    ))
                    .disabled(notifications.permissionRequestInFlight)
                    Text(notifications.statusText).font(.caption).foregroundStyle(.secondary)
                    Button("Notification Settings…") { notifications.openSystemSettings() }
                        .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(12)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Behavior

    private var behavior: some View {
        Section("Behavior") {
            VStack(spacing: 0) {
                settingRow {
                    Toggle("Launch at login", isOn: Binding(
                        get: { _ = preferences.launchAtLoginRevision; return preferences.launchAtLogin },
                        set: { preferences.launchAtLogin = $0 }
                    ))
                }
                Divider().padding(.leading, 12)
                settingRow { Toggle("Hide in full-screen apps", isOn: $preferences.hideInFullScreen) }
                Divider().padding(.leading, 12)
                settingRow { Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon) }
                Divider().padding(.leading, 12)
                settingRow {
                    HStack {
                        Text("Summon island")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .toggleIsland)
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func settingRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.system(size: 12.5))
            .padding(.horizontal, 12)
            .frame(height: 38)
    }

    @ViewBuilder
    private var updates: some View {
        if let updater {
            Section("App updates", footnote: "Update downloads are verified before installation. You choose when to install and restart.") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updater.automaticallyChecks },
                        set: { updater.setAutomaticallyChecks($0) }
                    ))
                    .disabled(!updater.isAvailable)
                }
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    // MARK: - About

    private var about: some View {
        Section("About") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Headroom")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? HeadroomCore.version) · read-only; never modifies your CLI logins")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link("GitHub", destination: URL(string: "https://github.com/PeytonNowlin/Headroom")!)
                    .font(.system(size: 12))
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct Section<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder let content: Content

    init(_ title: String, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            content
            if let footnote {
                Text(footnote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ProviderRow: View {
    let id: ProviderID
    var model: UsageModel
    @Bindable var preferences: Preferences

    var body: some View {
        let state = model.state(id)
        let status = model.status(id)
        HStack(spacing: 10) {
            // The exact gauge this provider shows beside the notch, live.
            Group {
                if CompactGauge.shows(state: state, status: status) {
                    CompactGauge(provider: id, state: state, status: status, size: 14)
                } else {
                    Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 1).frame(width: 12, height: 12)
                }
            }
            .frame(width: 16)
            ProviderGlyph(provider: id, size: 12)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(id.displayName).font(.system(size: 12.5, weight: .medium))
                Text(subtitle(state: state, status: status))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { preferences.tier(id) },
                set: { preferences.setTier($0, for: id) }
            )) {
                ForEach(ProviderTier.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 176)
            .accessibilityLabel("\(id.displayName) importance")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }

    private func subtitle(state: ProviderState?, status: ConnectionStatus) -> String {
        var parts: [String] = []
        if let plan = state?.snapshot?.planName { parts.append(plan) }
        if status == .expired {
            parts.append("login expired")
        } else if let used = state?.snapshot?.ringUsedPercent {
            parts.append("\(Int((100 - used).rounded()))% left")
        } else if !model.isDetected(id) {
            parts.append("not signed in")
        }
        return parts.joined(separator: " · ")
    }
}
