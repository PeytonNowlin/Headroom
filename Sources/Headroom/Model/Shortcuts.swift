import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Open and focus the island, or close keyboard navigation. Default ⌃⌥U; rebindable in Settings.
    static let toggleIsland = Self("toggleIsland", initial: .init(.u, modifiers: [.control, .option]))
}
