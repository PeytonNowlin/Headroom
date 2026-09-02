# Changelog

All notable changes to Headroom. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow semver.

## [Unreleased]

### Added

- Notch-anchored Liquid Glass island with per-provider compact dots and hover-to-expand rings for Claude, Codex, and Grok.
- Drill-in per provider: every quota window with reset countdowns, extra-usage balance, Codex reset credits, pace hints.
- Local spend tracking from CLI session logs: today, yesterday, and 30 days, per provider and combined, with token totals; pricing from LiteLLM with a bundled fallback.
- Pinning, global hotkey, right-click menu, optional menu bar icon, launch at login, hide in full screen, first-run guidance.
- Alert banners at 80% and 95% of any window and when pace projects exhaustion before reset.
- Next-refresh countdown; rate-limit cooldowns honor `Retry-After` and persist across relaunch.
