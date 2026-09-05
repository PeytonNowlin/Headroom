import HeadroomCore
import SwiftUI

/// Shared connection status and recovery actions for settings and provider details.
struct ConnectionView: View {
    let provider: ProviderID
    let state: ProviderState?
    let now: Date
    var onRetry: () -> Void

    private var status: ConnectionStatus { state?.status(at: now) ?? .absent }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(state?.freshness(at: now) ?? "Not signed in")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 8)
                Button(state?.isRefreshing == true ? "Checking…" : "Check again", action: onRetry)
                    .controlSize(.small)
                    .disabled(state?.isRefreshing == true || state?.isRateLimited(at: now) == true)
                    .accessibilityLabel("Check \(provider.displayName) connection again")
            }
            if status == .expired {
                Text(provider.reconnectHint)
            } else if status == .absent && state?.lastError == nil && state?.isRefreshing != true {
                Text(provider == .cursor ? "Open Cursor and sign in to your account, then check again." : "Open Terminal, run \(provider.signInCommand), and follow the sign-in prompts. Then check again.")
            }
            if state?.isRateLimited(at: now) == true, let until = state?.rateLimitedUntil {
                Text("The provider asked us to wait. Retry in \(Formatting.countdown(to: until, from: now)).")
            } else if let error = state?.lastError {
                Text("\(error). Check your connection and try again; your login has not been changed.")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
