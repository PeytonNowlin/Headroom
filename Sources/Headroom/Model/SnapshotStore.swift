import Foundation
import HeadroomCore

/// Persists per-provider state that should outlive a relaunch: the last good snapshot (shown as
/// stale while the first refresh runs) and any rate-limit cooldown (so a relaunch can't fire a
/// request the server just refused).
struct SnapshotStore {
    struct Entry: Codable {
        var snapshot: Snapshot?
        var rateLimitedUntil: Date?
    }

    let environment: HostEnvironment
    private var url: URL { environment.dataDirectory.appending(path: "snapshots.json") }

    func load() -> [ProviderID: Entry] {
        guard let data = try? environment.readFile(url) else { return [:] }
        let decoder = JSONDecoder.pricing
        var out: [ProviderID: Entry] = [:]
        if let decoded = try? decoder.decode([String: Entry].self, from: data) {
            for (key, entry) in decoded {
                guard let id = ProviderID(rawValue: key) else { continue }
                var e = entry
                if e.snapshot?.status == .absent { e.snapshot = nil }
                out[id] = e
            }
        } else if let legacy = try? decoder.decode([String: Snapshot].self, from: data) {
            for (key, snapshot) in legacy {
                if let id = ProviderID(rawValue: key), snapshot.status != .absent {
                    out[id] = Entry(snapshot: snapshot)
                }
            }
        }
        return out
    }

    func save(_ entries: [ProviderID: Entry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let keyed = Dictionary(uniqueKeysWithValues: entries.map { ($0.key.rawValue, $0.value) })
        if let data = try? encoder.encode(keyed) {
            try? environment.writeFile(url, data)
        }
    }
}
