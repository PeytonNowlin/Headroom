import HeadroomCore
import SwiftUI

/// The SwiftUI root of the island. Draws the silhouette for the current mode and lays content
/// inside it. Compact on a notch is bezel-black so it reads as part of the notch; everything
/// else is Liquid Glass.
struct IslandView: View {
    @Bindable var state: IslandState
    var model: UsageModel

    private var shape: IslandShape {
        IslandShape(cornerRadius: state.layout.cornerRadius, flare: state.layout.flare)
    }

    private var size: CGSize {
        let s = state.layout.size(for: state.mode)
        return CGSize(width: s.width + state.layout.flare * 2, height: s.height)
    }

    private var isBlackCompact: Bool {
        state.layout.anchor.isNotch && state.mode == .compact
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .opacity(isBlackCompact ? 1 : 0)
            Color.clear
                .glassEffect(.regular, in: shape)
                .opacity(isBlackCompact ? 0 : 1)
            content
                .padding(.horizontal, state.layout.flare)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .frame(width: state.layout.panel.width, height: state.layout.panel.height, alignment: .top)
        .animation(Motion.island, value: state.mode)
    }

    @ViewBuilder
    private var content: some View {
        switch state.mode {
        case .compact:
            compactContent
        case .expanded:
            expandedContent
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }

    // MARK: - Compact

    private var compactContent: some View {
        let providers = model.visibleProviders
        let split = (providers.count + 1) / 2
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(providers.prefix(split)) { dot($0) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear.frame(width: notchWidth)
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
            if state.layout.anchor.isNotch {
                Color.clear.frame(height: notchHeight)
            }
            let providers = model.visibleProviders
            if providers.isEmpty {
                VStack(spacing: 6) {
                    Text("Headroom")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("No AI CLI logins found")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 22)
            } else {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(providers) { id in
                        VStack(spacing: 6) {
                            RingView(provider: id, state: model.state(id), status: model.status(id))
                            Text(id.displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 18)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 14)
        .frame(width: state.layout.expanded.width, height: state.layout.expanded.height)
    }

    private var notchHeight: CGFloat {
        if case let .notch(_, height) = state.layout.anchor { return height }
        return 0
    }

    private var notchWidth: CGFloat {
        if case let .notch(width, _) = state.layout.anchor { return width }
        return 0
    }
}
