import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Toggle the island pinned open. Default ⌃⌥U; rebindable in Settings.
    static let toggleIsland = Self("toggleIsland", initial: .init(.u, modifiers: [.control, .option]))
}
