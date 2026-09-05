import HeadroomCore
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var model: UsageModel
    @Bindable var preferences: Preferences
    var updater: UpdateController?
    var notifications: NotificationController?
    var onOpenTrends: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                updates
                providers
                connections
                alerts
                legend
                behavior
                about
            }
            .padding(22)
        }
        .frame(width: 520)
        .frame(minHeight: 520, idealHeight: 620)
        .background(.regularMaterial)
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
                    Button("Usage Trends…", action: onOpenTrends)
                }
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Providers

    private var providers: some View {
        Section("Providers", footnote: "Automatic shows a provider when its CLI is signed in. Drag to reorder; the order sets ring and dot positions.") {
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

    private var alerts: some View {
        Section("Quota alerts", footnote: "Warnings appear at 80% and 95% used, or when a steady recent pace may exhaust quota. Quota-return banners require a confirmed reset after usage reached 80%. Snooze applies to each current window until its own reset.") {
            VStack(alignment: .leading, spacing: 14) {
                if let notifications {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Also send macOS notifications", isOn: Binding(
                            get: { notifications.enabled },
                            set: { enabled in Task { await notifications.setEnabled(enabled) } }
                        ))
                        .disabled(notifications.permissionRequestInFlight)
                        Text(notifications.statusText).font(.caption).foregroundStyle(.secondary)
                        Button("Notification Settings…") { notifications.openSystemSettings() }
                            .buttonStyle(.link)
                    }
                    Divider()
                }
                ForEach(preferences.order) { id in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(id.displayName).fontWeight(.medium)
                        Toggle("Quota warnings", isOn: Binding(
                            get: { preferences.alertOptions(id).warningsEnabled },
                            set: { value in
                                var options = preferences.alertOptions(id)
                                options.warningsEnabled = value
                                model.setAlertOptions(options, for: id)
                            }
                        ))
                        Toggle("Alert when quota returns", isOn: Binding(
                            get: { preferences.alertOptions(id).notifyOnReset },
                            set: { value in
                                var options = preferences.alertOptions(id)
                                options.notifyOnReset = value
                                model.setAlertOptions(options, for: id)
                            }
                        ))
                        if preferences.alertOptions(id).warningsEnabled {
                            Button(model.alertsSnoozed(id) ? "Resume warnings" : "Snooze until reset") {
                                if model.alertsSnoozed(id) { model.resumeAlerts(id) }
                                else { model.snoozeAlerts(id) }
                            }
                            .disabled(model.state(id)?.snapshot?.windows.contains { ($0.resetsAt.map { $0 > model.now } ?? false) } != true)
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(id.displayName + " alerts")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(size: 12))
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(12)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Legend

    private var legend: some View {
        Section("Dot & ring colors", footnote: "Dots summarize the most-constrained window. A hollow dot means 40–69% used, a dash means 70–89%, and ! means 90%+ or a connection problem. Faded dots show saved usage.") {
            HStack(spacing: 10) {
                legendItem(.fine, "< 40%")
                legendItem(.watch, "40–69%")
                legendItem(.warn, "70–89%")
                legendItem(.critical, "90%+")
                Spacer()
                HStack(spacing: 6) {
                    Text("!").font(.system(size: 11, weight: .heavy)).foregroundStyle(.secondary)
                    Text("Login expired").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func legendItem(_ urgency: Urgency, _ label: String) -> some View {
        HStack(spacing: 6) {
            Group {
                switch urgency {
                case .fine: Circle().frame(width: 8, height: 8)
                case .watch: Circle().strokeBorder(lineWidth: 1.5).frame(width: 8, height: 8)
                case .warn: Capsule().frame(width: 8, height: 3)
                case .critical: Text("!").font(.system(size: 11, weight: .heavy))
                }
            }
            .foregroundStyle(urgency.color(for: scheme))
            .frame(width: 8, height: 10)
            .accessibilityHidden(true)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
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
                        Text("Toggle island")
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let state = model.state(id)
        let status = model.status(id)
        HStack(spacing: 10) {
            // The exact dot this provider shows beside the notch, live.
            Group {
                if ProviderDot.shows(state: state, status: status) {
                    ProviderDot(state: state, status: status)
                } else {
                    Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
                }
            }
            .frame(width: 8, height: 10)
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
                get: { preferences.visibility(id) },
                set: { preferences.setVisibility($0, for: id) }
            )) {
                ForEach(ProviderVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 120)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }

    private func subtitle(state: ProviderState?, status: ConnectionStatus) -> String {
        var parts: [String] = []
        switch model.dotSide(id) {
        case .left: parts.append("Dot left of notch")
        case .right: parts.append("Dot right of notch")
        case .none: parts.append(model.visibleProviders.contains(id) ? "No dot — no quota data" : "Not detected")
        }
        if let plan = state?.snapshot?.planName { parts.append(plan) }
        if status == .expired { parts.append("login expired") }
        if let used = state?.snapshot?.ringUsedPercent, status != .expired {
            parts.append("\(Int((100 - used).rounded()))% left")
        }
        return parts.joined(separator: " · ")
    }
}
