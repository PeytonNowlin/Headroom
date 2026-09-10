import Foundation

/// Where OpenCode keeps its local data. Resolution mirrors OpenCode itself: an explicit
/// `OPENCODE_DATA_DIR` wins, then `$XDG_DATA_HOME/opencode`, then `~/.local/share/opencode`.
enum OpenCodePaths {
    static func dataDirectory(_ environment: HostEnvironment) -> URL {
        if let override = environment.environmentVariable("OPENCODE_DATA_DIR")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return environment.path(override)
        }
        if let xdg = environment.environmentVariable("XDG_DATA_HOME")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !xdg.isEmpty {
            return environment.path(xdg).appending(path: "opencode")
        }
        return environment.home.appending(path: ".local/share/opencode")
    }

    static func authFile(_ environment: HostEnvironment) -> URL {
        dataDirectory(environment).appending(path: "auth.json")
    }

    /// Every `opencode*.db` directly inside the data directory. OpenCode partitions its database by
    /// release channel (`opencode.db` for stable, `opencode-next.db` for the preview line), so all
    /// channels are read. Listed shallowly on purpose — the data directory also holds repo snapshots
    /// that a recursive walk would crawl. The `.db` suffix excludes the `-wal`/`-shm` sidecars.
    static func databases(_ environment: HostEnvironment) -> [URL] {
        let directory = dataDirectory(environment)
        return environment.directoryEntries(directory)
            .filter { $0.hasPrefix("opencode") && $0.hasSuffix(".db") }
            .sorted()
            .map { directory.appending(path: $0) }
    }
}
