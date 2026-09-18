import HeadroomCore
import SwiftUI

/// The SwiftUI root of the island. Draws the silhouette for the current mode and lays content
/// inside it. Compact on a notch is bezel-black so it reads as part of the notch; everything
/// else is Liquid Glass. Dormant draws nothing at all.
struct IslandView: View {
    @Bindable var state: IslandState
    var model: UsageModel
    var onSelect: (ProviderID?) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    @FocusState private var focusedProvider: ProviderID?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: IslandShape {
        IslandShape(cornerRadius: state.layout.cornerRadius, flare: state.layout.flare)
    }

    private var size: CGSize {
        let s = state.currentSize
        return CGSize(width: s.width + state.layout.flare * 2, height: s.height)
    }

    /// Solid bezel instead of glass while compact, so the band reads as the notch.
    private var isBlack: Bool {
        state.mode == .compact
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The glass is permanent and untouched: never inserted or removed, never masked, never
            // faded. Any of those makes Core Animation rasterize its backdrop layer offscreen, where
            // it can't sample the desktop, and the island (or the whole panel) paints black. So the
            // bezel is an opaque overlay on top of it, only the content is clipped, and a dormant
            // island is made to vanish by giving it zero height rather than by hiding the glass.
            Color.clear
                .glassEffect(.regular, in: shape)
            if isBlack {
                shape.fill(.black)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
            content
                .padding(.horizontal, state.layout.flare)
                .environment(\.colorScheme, isBlack ? .dark : colorScheme)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .frame(width: state.layout.panel.width, height: state.layout.panel.height, alignment: .top)
        .overlay(alignment: .top) {
            if state.mode.isCompact, let provider = state.hoveredProvider, model.activeAlert == nil {
                VStack(alignment: .leading, spacing: 3) {
                    Text(provider.displayName).font(.caption.bold())
                    Text(providerDescription(provider)).font(.caption)
                }
                .padding(10)
                .frame(width: 240, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, size.height + 6)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if let alert = model.activeAlert {
                AlertBanner(alert: alert)
                    .padding(.top, size.height + 8)
                    .transition(Motion.bannerTransition)
                    .id(alert.id)
            }
        }
        .animation(Motion.island, value: state.mode)
        .animation(Motion.island, value: state.content)
        .animation(Motion.island, value: model.activeAlert?.id)
        .onChange(of: state.focusedProvider) { _, id in focusedProvider = id }
        .onChange(of: focusedProvider) { _, id in
            state.focusedProvider = id
        }
        .onChange(of: state.keyboardNavigation) { _, active in
            if active { focusedProvider = state.focusedProvider }
        }
        .onChange(of: model.visibleProviders) { _, providers in
            if let focused = state.focusedProvider, !providers.contains(focused) {
                state.focusedProvider = providers.first
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.mode {
        case .dormant:
            Color.clear
        case .compact:
            compactContent
        case .expanded:
            expandedContent
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        case let .detail(id):
            detailContent(id)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }

    // MARK: - Compact

    /// Only the providers with something to say, main agents left of the notch and side
    /// providers right of it. Geometry mirrored in `IslandGeometry.compactProvider`.
    private var compactContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: CompactMetrics.spacing) {
                ForEach(model.compactMain) { gauge($0, size: CompactMetrics.mainSize) }
            }
            .padding(.trailing, CompactMetrics.notchInset)
            .frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear.frame(width: state.layout.anchor.compactGap)
            HStack(spacing: CompactMetrics.spacing) {
                ForEach(model.compactSecondary) { gauge($0, size: CompactMetrics.secondarySize) }
            }
            .padding(.leading, CompactMetrics.notchInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: state.currentSize.width, height: state.layout.compact.height)
    }

    private func providerDescription(_ id: ProviderID) -> String {
        let state = model.state(id)
        var parts = [quotaDescription(id)]
        if let window = state?.snapshot?.limitingWindow, let resets = window.resetsAt, resets > model.now {
            parts.append("back in \(Formatting.countdown(to: resets, from: model.now))")
        }
        if model.status(id) == .expired { parts.append("login expired") }
        else if state?.lastError != nil { parts.append("can't reach it") }
        return parts.joined(separator: " · ")
    }

    private func quotaDescription(_ id: ProviderID) -> String {
        guard let remaining = model.state(id)?.snapshot?.ringRemainingPercent else { return "No quota reported" }
        return "\(Int(remaining.rounded()))% left"
    }

    private func gauge(_ id: ProviderID, size: CGFloat) -> some View {
        Button { onSelect(id) } label: {
            CompactGauge(provider: id, state: model.state(id), status: model.status(id),
                         size: size, resetAt: model.resetSignals[id])
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(id.displayName)
        .accessibilityValue(providerDescription(id))
        .accessibilityHint("Open quota details")
        .foregroundStyle(Color.white)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            notchSpacer
            if model.visibleProviders.isEmpty {
                emptyState
            } else {
                VStack(spacing: 14) {
                    if !model.mainProviders.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(model.mainProviders) { mainTile($0) }
                        }
                    }
                    if !model.secondaryProviders.isEmpty {
                        HStack(spacing: 14) {
                            ForEach(model.secondaryProviders) { sideTile($0) }
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 14)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            state.content.expandedHeight = height
        }
        .overlay(alignment: .topTrailing) {
            if state.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(45))
                    .padding(.top, state.layout.anchor.notchHeight + 8)
                    .padding(.trailing, 12)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            RefreshCountdown(model: model)
                .padding(.top, state.layout.anchor.notchHeight + 7)
                .padding(.leading, 12)
        }
        .frame(width: state.layout.expandedWidth)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Headroom")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("Sign in to Claude, Codex, Grok, Cursor, or OpenCode and their quota shows up here.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Button("Set up providers…", action: onOpenSettings)
                .controlSize(.small)
                .buttonStyle(.glass)
                .padding(.top, 2)
            Button("Check again") { model.refreshAll() }
                .controlSize(.small)
                .disabled(model.isAnyRefreshing)
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    /// A main agent: the full ring, its name, and how long until the quota comes back.
    private func mainTile(_ id: ProviderID) -> some View {
        providerButton(id) {
            VStack(spacing: 6) {
                RingView(provider: id, state: model.state(id), status: model.status(id))
                Text(id.displayName)
                    .font(.system(size: 11, weight: .medium))
                Text(resetLine(id))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(width: 90)
        }
    }

    /// A side provider: a smaller ring and its name. No countdown — you are not waiting on it.
    private func sideTile(_ id: ProviderID) -> some View {
        providerButton(id) {
            VStack(spacing: 4) {
                RingView(provider: id, state: model.state(id), status: model.status(id),
                         diameter: 30, lineWidth: 2.5)
                Text(id.displayName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 62)
        }
    }

    private func providerButton<Content: View>(_ id: ProviderID, @ViewBuilder _ label: () -> Content) -> some View {
        Button { onSelect(id) } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(LiftButtonStyle())
        .focusable()
        .focused($focusedProvider, equals: id)
        .focusEffectDisabled()
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(-4)
                .opacity(state.keyboardNavigation && state.focusedProvider == id ? 1 : 0)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(id.displayName)
        .accessibilityValue(providerDescription(id))
        .accessibilityHint("Open quota details for \(id.displayName)")
    }

    /// When the limiting quota comes back, or what is wrong instead. Never both, never jargon.
    private func resetLine(_ id: ProviderID) -> String {
        if model.status(id) == .expired { return "Signed out" }
        if model.state(id)?.lastError != nil { return "Can't reach it" }
        guard let window = model.state(id)?.snapshot?.limitingWindow else { return "" }
        guard let resets = window.resetsAt else { return "" }
        return resets > model.now ? "Back in \(Formatting.countdown(to: resets, from: model.now))" : "Resetting"
    }

    // MARK: - Detail

    private func detailContent(_ id: ProviderID) -> some View {
        VStack(spacing: 0) {
            notchSpacer
            ScrollView {
                DetailView(
                    provider: id,
                    state: model.state(id),
                    status: model.status(id),
                    now: model.now,
                    model: model,
                    onBack: { onSelect(nil) }
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    state.content.detailHeight = height + state.layout.anchor.notchHeight
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: state.layout.expandedWidth, alignment: .top)
        .frame(height: state.currentSize.height, alignment: .top)
    }

    /// Keeps content out of the hardware notch's band; collapses to nothing when simulated.
    private var notchSpacer: some View {
        Color.clear.frame(height: state.layout.anchor.notchHeight)
    }
}

/// Tokenly's hover lift / press squash.
struct LiftButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : (hovering ? 1.08 : 1)))
            .animation(Motion.lift, value: configuration.isPressed)
            .animation(Motion.lift, value: hovering)
            .onHover { hovering = $0 }
    }
}
