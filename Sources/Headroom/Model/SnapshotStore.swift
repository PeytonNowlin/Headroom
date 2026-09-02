import Foundation
import HeadroomCore

/// Persists the last good snapshot per provider so a relaunch shows yesterday's numbers as
/// stale instead of a blank island while the first refresh (or a rate-limit backoff) runs.
struct SnapshotStore {
    let environment: HostEnvironment
    private var url: URL { environment.dataDirectory.appending(path: "snapshots.json") }

    func load() -> [ProviderID: Snapshot] {
        guard let data = try? environment.readFile(url),
              let decoded = try? JSONDecoder.pricing.decode([String: Snapshot].self, from: data) else { return [:] }
        var out: [ProviderID: Snapshot] = [:]
        for (key, snapshot) in decoded {
            if let id = ProviderID(rawValue: key), snapshot.status != .absent { out[id] = snapshot }
        }
        return out
    }

    func save(_ snapshots: [ProviderID: Snapshot]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let keyed = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key.rawValue, $0.value) })
        if let data = try? encoder.encode(keyed) {
            try? environment.writeFile(url, data)
        }
    }
}
