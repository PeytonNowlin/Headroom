# Changelog

All notable changes to Headroom. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow semver.

## [Unreleased]

## [0.2.1] - 2026-09-02

### Fixed

- Fixed release builds crashing at launch on other Macs because SwiftPM resource bundles were packaged somewhere the generated bundle loader could not find them.

## [0.2.0] - 2026-09-02

### Changed

- The island now appears on every connected display, not just the built-in one. Hover expands the island under the cursor; pinning applies to all of them. Displays without a hardware notch get a simulated one (black band flush with the top edge) in place of the old floating pill.
- "Hide in full-screen apps" hides only the island on the display showing the full-screen app.

## [0.1.0] - 2026-09-02

First release.

### Added

- Notch-anchored Liquid Glass island with per-provider compact dots and hover-to-expand rings for Claude, Codex, Grok, and Cursor.
- Cursor: included-usage, Cursor-models, other-models, and Grok Bot windows plus on-demand spend, read from the Cursor app's login; spend from the dashboard usage export, priced locally with OpenUsage's pricing supplement (Cursor-native models and slug aliases).
- Drill-in per provider: every quota window with reset countdowns, extra-usage balance, Codex reset credits, pace hints.
- Local spend tracking from CLI session logs: today, yesterday, and 30 days, per provider and combined, with token totals; pricing from LiteLLM with a bundled fallback.
- Pinning, global hotkey, right-click menu, optional menu bar icon, launch at login, first-run guidance.
- Stays visible over full-screen apps by default; an optional setting hides it instead.
- Alert banners at 80% and 95% of any window and when pace projects exhaustion before reset.
- Next-refresh countdown; rate-limit cooldowns honor `Retry-After` and persist across relaunch.

[Unreleased]: https://github.com/PeytonNowlin/Headroom/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/PeytonNowlin/Headroom/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/PeytonNowlin/Headroom/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/PeytonNowlin/Headroom/releases/tag/v0.1.0
