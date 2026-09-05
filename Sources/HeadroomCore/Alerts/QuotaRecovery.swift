import Foundation

/// A compact reset cue needs confirmed replenishment, not merely a countdown reaching zero.
public enum QuotaRecovery {
    public static func confirmed(_ current: Snapshot, after previous: Snapshot?, now: Date) -> Bool {
        guard let previous, previous.provider == current.provider,
              previous.status == .connected, current.status == .connected,
              previous.fetchedAt < current.fetchedAt, current.fetchedAt <= now,
              now.timeIntervalSince(previous.fetchedAt) <= 15 * 60,
              now.timeIntervalSince(current.fetchedAt) <= 10 * 60,
              let oldRemaining = previous.ringRemainingPercent,
              let remaining = current.ringRemainingPercent,
              remaining > oldRemaining else { return false }
        return current.windows.contains { window in
            guard let old = previous.windows.first(where: { $0.id == window.id }),
                  old.usedPercent.isFinite, window.usedPercent.isFinite,
                  window.usedPercent < old.usedPercent,
                  let reset = old.resetsAt, reset <= current.fetchedAt else { return false }
            if !window.isStarted { return window.usedPercent == 0 && window.resetsAt == nil }
            return window.resetsAt.map { $0 > reset && $0 > now } ?? false
        }
    }
}
