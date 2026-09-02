import SwiftUI

/// The SwiftUI root of the island. Draws the silhouette for the current mode and lays content
/// inside it. Compact on a notch is bezel-black so it reads as part of the notch; everything
/// else is Liquid Glass.
struct IslandView: View {
    @Bindable var state: IslandState

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

    private var compactContent: some View {
        HStack {
            Circle().fill(Color(red: 0.196, green: 0.843, blue: 0.294)).frame(width: 6, height: 6)
            Spacer()
            Circle().fill(Color(red: 0.894, green: 1.0, blue: 0.102)).frame(width: 6, height: 6)
        }
        .padding(.horizontal, 16)
        .frame(height: state.layout.compact.height)
    }

    private var expandedContent: some View {
        VStack(spacing: 12) {
            if state.layout.anchor.isNotch {
                Color.clear.frame(height: notchHeight)
            }
            Text("Headroom")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("No providers connected yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(width: state.layout.expanded.width, height: state.layout.expanded.height)
    }

    private var notchHeight: CGFloat {
        if case let .notch(_, height) = state.layout.anchor { return height }
        return 0
    }
}
