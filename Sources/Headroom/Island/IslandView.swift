import HeadroomCore
import SwiftUI

/// The SwiftUI root of the island. Draws the silhouette for the current mode and lays content
/// inside it. Compact on a notch is bezel-black so it reads as part of the notch; everything
/// else is Liquid Glass.
struct IslandView: View {
    @Bindable var state: IslandState
    var model: UsageModel
    var onSelect: (ProviderID?) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var onOpenTrends: (ProviderID?) -> Void = { _ in }
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
            // bezel is an opaque overlay on top of it, and only the content is clipped.
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
            if let alert = model.activeAlert {
                AlertBanner(alert: alert)
                    .padding(.top, size.height + 8)
                    .transition(Motion.bannerTransition)
                    .id(alert.id)
            }
        }
        .animation(Motion.island, value: state.mode)
        .animation(Motion.island, value: state.detailHeight)
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

    private var compactContent: some View {
        let providers = model.dotProviders
        let split = (providers.count + 1) / 2
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(providers.prefix(split)) { dot($0) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear.frame(width: state.layout.anchor.compactGap)
            HStack(spacing: 6) {
                ForEach(providers.dropFirst(split)) { dot($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(width: state.layout.compact.width, height: state.layout.compact.height)
    }

    private func dot(_ id: ProviderID) -> some View {
        ProviderDot(state: model.state(id), status: model.status(id))
            .accessibilityLabel("\(id.displayName), \(model.state(id)?.freshness(at: model.now) ?? "Not signed in")")
            .accessibilityValue(model.state(id)?.snapshot?.ringRemainingPercent.map { "\(Int($0.rounded())) percent remaining" } ?? "Quota unavailable")
            .foregroundStyle(Color.white)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            notchSpacer
            let providers = model.visibleProviders
            if providers.isEmpty {
                VStack(spacing: 8) {
                    Text("Headroom")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Connect Claude, Codex, Grok, or Cursor in Settings to see your available quota.")
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
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(providers) { id in
                        Button {
                            onSelect(id)
                        } label: {
                            VStack(spacing: 6) {
                                RingView(provider: id, state: model.state(id), status: model.status(id))
                                Text(id.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                if let window = model.state(id)?.snapshot?.limitingWindow,
                                   model.status(id) != .expired {
                                    Text(window.title)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(window.resetsAt.map { $0 > model.now ? "Resets in \(Formatting.countdown(to: $0, from: model.now))" : "Awaiting reset" } ?? "Reset not reported")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Text(model.state(id)?.freshness(at: model.now) ?? "Not signed in")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .multilineTextAlignment(.center)
                            .frame(width: 90)
                            .contentShape(Rectangle())
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
                        .accessibilityHint("Open quota details for \(id.displayName)")
                    }
                }
                .padding(.top, 18)
            }
            Spacer(minLength: 0)
            if let total = model.totalSpend {
                Button { onOpenTrends(nil) } label: { SpendFooter(summary: total) }
                    .buttonStyle(.plain)
                    .help("Open usage trends")
                    .accessibilityLabel("Usage trends, estimated token value")
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 12)
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
        .frame(width: state.layout.expandedWidth, height: state.layout.expandedHeight)
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
                    spend: model.spend[id],
                    model: model,
                    onOpenTrends: { onOpenTrends(id) },
                    onBack: { onSelect(nil) }
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    state.detailHeight = height + state.layout.anchor.notchHeight
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
