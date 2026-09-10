# Changelog

All notable changes to Headroom. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow semver.

## [Unreleased]

## [0.5.0] - 2026-09-10

### Added

- OpenCode Go as a tracked provider: Session, Weekly, and Monthly quota windows from OpenCode's own usage API, read with the `opencode-go` key the OpenCode CLI already holds. Accounts on Zen pay-as-you-go stay connected and show spend only, with a note explaining the missing rings.
- OpenCode spend tiles and trends, summed from the per-message cost OpenCode records in its local database (all release channels). The database is opened read-only off the main thread, on the same background cadence as Cursor spend.

## [0.4.2] - 2026-09-08

### Fixed

- Hide in full-screen apps now recognizes Chrome windows whose toolbar and content are exposed as separate windows.

## [0.4.1] - 2026-09-05

### Changed

- Compact LEDs now show remaining quota as tiny gauges with direct provider click targets and hover labels for quota, reset, and freshness.
- Gauges pulse once after fresh provider data confirms a reset that restores headroom. The pulse respects Reduce Motion and does not depend on notification settings.

## [0.4.0] - 2026-09-05

### Added

- Signed in-app updates powered by Sparkle, with Check for Updates and optional automatic checks. Release archives and update feeds use a dedicated Ed25519 signing key.
- Opt-in macOS quota notifications with Open Provider and Snooze Until Reset actions, following the existing warning and quota-return settings.
- Seven- and thirty-day usage trends with daily estimated token value, per-model attribution, and explicit missing-data and partial-price labels.
- Keyboard access: the global shortcut focuses the island, arrows select providers, Return opens details, Tab traverses controls, and Escape closes it and restores the previous app.

### Changed

- Countdown updates slow to once per minute when all interactive surfaces are closed; visible surfaces retain one-second updates.
- Background local-log scans run every five minutes while idle and every two minutes while visible. Opening a surface wakes the scan schedule; unchanged logs avoid repeated reads, aggregation, and cache writes.

## [0.3.0] - 2026-09-05

### Added

- Each provider ring now identifies its limiting quota window and shows its reset countdown and freshness, including explicit saved-data and failed-refresh states.
- Recent-usage forecasts backed by a bounded local history of quota percentages. Forecasts compare recent and whole-window pace, require enough fresh observations, and suppress pace warnings for bursty usage.
- Per-provider quota warning controls, snooze until each current window resets, and opt-in banners when a confirmed reset restores quota after high usage.
- Provider-specific sign-in and reconnect guidance with individual **Check again** actions that respect rate-limit cooldowns.
- Non-color compact status indicators and descriptive accessibility labels. Repeating ring animations respect Reduce Motion.

### Changed

- Token costs are clearly labeled **Estimated token value**, with missing prices disclosed in both detail tiles and the combined footer. Provider-reported extra usage remains separate.
- Threshold and pace warnings for the same window are combined into one readable banner.
- The expanded island gives quota context more room; long provider details scroll within the panel.
- Existing provider order, visibility, and behavior preferences are preserved when alert settings are introduced.

### Fixed

- Restored quota snapshots are identified as saved data until a successful refresh.
- Quota-return banners also recognize Claude sessions that reset to an idle, unused state before the next session starts.
- Downloaded release checksums refer to the DMG filename rather than a local build directory.

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

[Unreleased]: https://github.com/PeytonNowlin/Headroom/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/PeytonNowlin/Headroom/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/PeytonNowlin/Headroom/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/PeytonNowlin/Headroom/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/PeytonNowlin/Headroom/releases/tag/v0.1.0
