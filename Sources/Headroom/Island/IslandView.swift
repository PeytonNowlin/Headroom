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

    private var shape: IslandShape {
        IslandShape(cornerRadius: state.layout.cornerRadius, flare: state.layout.flare)
    }

    private var size: CGSize {
        let s = state.currentSize
        return CGSize(width: s.width + state.layout.flare * 2, height: s.height)
    }

    private var isBlackCompact: Bool {
        state.layout.anchor.isNotch && state.mode == .compact
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Gate the glass with `if`, never opacity: a glass view faded to 0 still owns a backdrop
            // layer, and when that layer is rasterized offscreen in a transparent window it can't
            // sample the desktop and paints the whole panel black until the compositor recovers.
            if isBlackCompact {
                shape.fill(.black)
            } else {
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .glassEffectTransition(.materialize)
            }
            content
                .padding(.horizontal, state.layout.flare)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
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
    }

    @ViewBuilder
    private var content: some View {
        switch state.mode {
        case .compact:
            compactContent
        case .expanded:
            expandedContent
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        case let .detail(id):
            detailContent(id)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
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
            Color.clear.frame(width: state.layout.anchor.notchWidth)
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
                    Text("No AI logins found — sign in with `claude`, `codex`, `grok`, or the Cursor app and the ring appears within a few minutes.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                    Button("Settings…", action: onOpenSettings)
                        .controlSize(.small)
                        .buttonStyle(.glass)
                        .padding(.top, 2)
                }
                .padding(.top, 16)
            } else {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(providers) { id in
                        Button {
                            onSelect(id)
                        } label: {
                            VStack(spacing: 6) {
                                RingView(provider: id, state: model.state(id), status: model.status(id))
                                Text(id.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(LiftButtonStyle())
                    }
                }
                .padding(.top, 18)
            }
            Spacer(minLength: 0)
            if let total = model.totalSpend {
                SpendFooter(summary: total)
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
            DetailView(
                provider: id,
                state: model.state(id),
                status: model.status(id),
                now: model.now,
                spend: model.spend[id],
                onBack: { onSelect(nil) }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                state.detailHeight = height + state.layout.anchor.notchHeight
            }
        }
        .frame(width: state.layout.expandedWidth, alignment: .top)
        .frame(height: state.currentSize.height, alignment: .top)
    }

    @ViewBuilder
    private var notchSpacer: some View {
        if state.layout.anchor.isNotch {
            Color.clear.frame(height: state.layout.anchor.notchHeight)
        }
    }
}

/// Tokenly's hover lift / press squash.
struct LiftButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : (hovering ? 1.08 : 1))
            .animation(Motion.lift, value: configuration.isPressed)
            .animation(Motion.lift, value: hovering)
            .onHover { hovering = $0 }
    }
}
