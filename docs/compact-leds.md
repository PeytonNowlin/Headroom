# Compact quota LEDs

Replace compact status dots with 9-point remaining-quota gauges in 14-point click targets. Keep urgency color and distinct connection/error states. Hovering a gauge shows provider quota, reset, and freshness context without expanding the island; clicking opens that provider. Hovering the rest of the island retains the usual expansion.

Pulse once when consecutive fresh live observations confirm a reset that increases overall headroom. Do not pulse on startup, failed refreshes, quota corrections, or elapsed countdowns alone. This visual cue is independent of notification preferences and respects Reduce Motion. Keep display-local hover/detail state and shared pinning.

Validate gauge layouts, compact hit targets on both display types, recovery detection, and the existing native keyboard path.

Validation: 92 tests pass, including recovery suppression and hit targets for one to four providers on hardware and simulated notches. Native macOS interaction confirmed that hovering a 14-point gauge reveals its provider label while remaining compact, and clicking opens provider details. Synthetic native captures cover full-to-empty gauges and hover text; they do not reproduce desktop glass composition. Hover labels use the visible-surface clock so countdowns refresh while shown.
