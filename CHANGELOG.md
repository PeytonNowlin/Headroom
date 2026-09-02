# Changelog

All notable changes to Headroom. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow semver.

## [Unreleased]

### Added

- Notch-anchored Liquid Glass island with per-provider compact dots and hover-to-expand rings for Claude, Codex, Grok, and Cursor.
- Cursor: included-usage, Cursor-models, other-models, and Grok Bot windows plus on-demand spend, read from the Cursor app's login; spend from the dashboard usage export, priced locally with OpenUsage's pricing supplement (Cursor-native models and slug aliases).
- Drill-in per provider: every quota window with reset countdowns, extra-usage balance, Codex reset credits, pace hints.
- Local spend tracking from CLI session logs: today, yesterday, and 30 days, per provider and combined, with token totals; pricing from LiteLLM with a bundled fallback.
- Pinning, global hotkey, right-click menu, optional menu bar icon, launch at login, first-run guidance.
- Stays visible over full-screen apps by default, drawn as a solid bezel there (glass can't sample a full-screen backdrop); an optional setting hides it instead.
- Alert banners at 80% and 95% of any window and when pace projects exhaustion before reset.
- Next-refresh countdown; rate-limit cooldowns honor `Retry-After` and persist across relaunch.
