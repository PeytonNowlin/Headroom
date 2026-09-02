import HeadroomCore
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var model: UsageModel
    @Bindable var preferences: Preferences
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                providers
                legend
                behavior
                about
            }
            .padding(22)
        }
        .frame(width: 440)
        .frame(minHeight: 520, idealHeight: 620)
        .background(.regularMaterial)
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

    // MARK: - Legend

    private var legend: some View {
        Section("Dot & ring colors", footnote: "Each dot beside the notch is one provider's most-constrained quota window, keyed on percent used.") {
            HStack(spacing: 14) {
                legendItem(.fine, "< 40%")
                legendItem(.watch, "40–69%")
                legendItem(.warn, "70–89%")
                legendItem(.critical, "90%+")
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(.secondary.opacity(0.6)).frame(width: 8, height: 8)
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
            Circle().fill(urgency.color(for: scheme)).frame(width: 8, height: 8)
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
            Circle()
                .fill(ProviderDot.color(state: state, status: status, scheme: scheme) ?? .clear)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: ProviderDot.shows(state: state, status: status) ? 0 : 1))
                .frame(width: 8, height: 8)
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
