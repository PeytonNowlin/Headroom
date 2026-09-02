---
status: accepted
---

# One island per display, drawn as a notch everywhere

Headroom 0.1.0 showed a single island on the main display only, and on displays without a hardware notch it fell back to a floating pill under the menu bar. Real-world use with an external monitor showed both choices were wrong: the usage lights were on the laptop screen while the work was on the external one, and the pill sat over window content with nothing to anchor it (external displays often reserve no menu bar at all).

We now run one `IslandInstance` per `NSScreen`, keyed by display ID and reconciled on every screen-parameter change, and every instance draws as a bezel-black band flush with the top edge. On a display without a notch the band is a simulated notch (32pt, or the menu bar height if taller) rather than a pill, so the island reads the same on every screen.

## Consequences

- Hover, expand, and detail are per display (the cursor is only on one). Pinning is shared: pin from any island, hotkey, or menu and all islands pin; a click outside every island unpins.
- Full-screen detection is per display. With "Displays have separate Spaces" off there is one menu bar, so its visibility is read from the primary display while the covering window is matched per display.
- A display that disappears takes its island with it; a new display gets a fresh island inheriting the current pinned state.
