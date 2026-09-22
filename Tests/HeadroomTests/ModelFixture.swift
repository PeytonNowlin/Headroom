import Foundation
import HeadroomCore
@testable import Headroom

/// A `UsageModel` seeded from saved snapshots, with no network, no filesystem, and no polling
/// started — enough to exercise everything that decides what the island shows.
@MainActor
enum ModelFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func snapshot(_ provider: ProviderID, used: Double, status: ConnectionStatus = .connected) -> Snapshot {
        Snapshot(provider: provider, fetchedAt: now, status: status, planName: "Pro",
                 windows: status == .connected
                     ? [QuotaWindow(id: "session", title: "Session", usedPercent: used,
                                    resetsAt: now.addingTimeInterval(7200), duration: 18000)]
                     : [])
    }

    static func environment(_ snapshots: [Snapshot]) -> HostEnvironment {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let saved = (try? encoder.encode(Dictionary(uniqueKeysWithValues: snapshots.map {
            ($0.provider.rawValue, SnapshotStore.Entry(snapshot: $0))
        }))) ?? Data()
        return HostEnvironment(
            home: URL(filePath: "/tmp/headroom-model-fixture"), timeZone: .gmt,
            readFile: { url in
                guard url.lastPathComponent == "snapshots.json" else { throw CocoaError(.fileReadNoSuchFile) }
                return saved
            },
            fileExists: { _ in false }, keychainPassword: { _ in nil }, environmentVariable: { _ in nil },
            send: { _ in HTTPResponse(statusCode: 503) }, now: { now },
            sleep: { try await Task.sleep(for: $0) })
    }

    /// A model where every listed provider reports one window at the given percent used.
    static func model(used: [ProviderID: Double], preferences: Preferences,
                      expired: Set<ProviderID> = []) -> UsageModel {
        let snapshots = used.map { snapshot($0.key, used: $0.value) }
            + expired.map { snapshot($0, used: 0, status: .expired) }
        return UsageModel(environment: environment(snapshots), preferences: preferences)
    }
}
