<p align="center">
  <img src="assets/headroom-logo.png" alt="Headroom" width="720">
</p>

# Headroom

A quota island for your MacBook notch. Headroom shows how much headroom you have left on Claude, Codex, Grok, Cursor, and OpenCode Go — as tiny dots beside the notch, as draining rings when you hover, and as full quota windows, reset countdowns, and local spend when you click in.

- **Compact**: a tiny remaining-quota gauge per provider, colored by urgency (green → yellow → orange → red). Hover a gauge for quota/reset context; click it to open that provider.
- **Hover**: rings per provider showing percent remaining, the limiting window, its reset countdown, and when usage was last checked. The footer shows estimated token value and tokens for today / yesterday / 30 days.
- **Click a ring**: every quota window with its reset time and recent versus whole-window pace, provider-reported extra usage, Codex reset credits, and estimated token value. Retry a connection or snooze warnings here.
- **Alerts**: one combined banner per window for 80% / 95% usage and confident recent-pace warnings. Settings offers per-provider warnings, snooze until each current window resets, and opt-in banners when a confirmed reset restores quota after 80%+ usage.

Headroom reads the same credentials your CLIs already use and the same session logs they already write. It never writes to them, never phones home, and has no telemetry.

## Requirements

- macOS 26 (Tahoe) or later, Apple silicon.
- An island on every display: with a notch the island wraps it; without one it draws a small notch of its own at the top center.
- At least one of the [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), [Grok](https://x.ai), or [OpenCode](https://opencode.ai) CLIs signed in, or the [Cursor](https://cursor.com) app.

## Install

1. Download `Headroom-x.y.z.dmg` from the [latest release](https://github.com/PeytonNowlin/Headroom/releases/latest). Each release also ships a `.sha256` file if you want to verify the download: `shasum -a 256 -c Headroom-x.y.z.dmg.sha256`.
2. Open the DMG and drag Headroom to Applications.
3. **First launch**: Headroom is ad-hoc signed, not notarized, so Gatekeeper blocks the first open. Double-click `Headroom.app`, dismiss the dialog, then go to **System Settings → Privacy & Security**, scroll to the Security section, and click **Open Anyway** next to Headroom. You only need to do this once.
4. Headroom registers itself as a login item on first run (macOS shows a "Login Items" notification); turn that off in Settings if you prefer.

If macOS says the app is "damaged", clear the quarantine flag instead: `xattr -dr com.apple.quarantine /Applications/Headroom.app`.

## Using it

| Action | Result |
| --- | --- |
| Hover a compact gauge | Show provider quota, reset, and freshness |
| Click a compact gauge | Open that provider directly |
| Hover the rest of the notch | Expand to rings |
| Click a ring | Drill into that provider |
| Right-click | Refresh, pin open, trends, updates, settings, quit |
| `⌃⌥U` (customizable) | Open and focus the island; press again to close |
| Arrow keys / Return | Select a provider / open its details |
| Tab / Shift-Tab / Escape | Traverse controls / close and restore the previous app |
| Click empty island while pinned | Unpin |

Providers refresh every 5 minutes; the countdown in the island's corner shows when. Refresh Now is in the right-click menu. If a provider rate-limits us, Headroom waits out the cooldown rather than retrying.

Settings includes provider-specific sign-in guidance and **Check again** actions. Missing logins, expired credentials, failed refreshes, rate-limit cooldowns, and saved usage have distinct status messages.

Forecasts use up to an hour of local quota observations. They require at least three samples spanning ten minutes, restart after gaps or quota corrections, and suppress pace warnings when usage is bursty. They are estimates assuming the observed pace continues. Saved or failing data does not produce a forecast.

**Estimated token value is not your subscription bill.** Values use model token prices or recorded costs. An asterisk marks a partial estimate with unknown model prices; provider-reported extra usage is shown separately.

Compact gauges drain with remaining quota, so color is not the only signal. An empty ring means no remaining headroom; `!` indicates a connection problem. A single soft pulse marks a confirmed reset that restores headroom, independent of notification settings. Saved data and elapsed countdowns do not trigger it. Reduce Motion disables the pulse.

Open **Usage Trends** from the menu, the estimated-value footer, or provider details to compare seven or thirty calendar days and see value by model. Missing records remain gaps; unknown prices are excluded from dollar totals and disclosed.

Enable **macOS notifications** in Settings to request permission for quota alerts. Notifications offer **Open Provider** and **Snooze Until Reset**; the island banners continue to work without notification permission.

Use **Check for Updates** in the menu or Settings. Automatic checks are optional; downloads and the update feed are cryptographically signed. This first updater-enabled version requires the usual manual installation; subsequent releases can install in-app.

## Privacy

- Credentials are read from where the CLIs keep them (Keychain for Claude, `~/.codex/auth.json`, `~/.grok/auth.json`, the `opencode-go` key in `~/.local/share/opencode/auth.json`, Cursor's state database opened read-only) and are only ever used to call each vendor's own usage endpoint. Headroom never writes credentials and never refreshes tokens.
- Spend is computed locally from session logs (`~/.claude/projects`, `~/.codex/sessions`, `~/.grok/sessions`). Cursor has no local log, so its last 30 days are fetched from your own Cursor dashboard export and priced locally. OpenCode records what each message cost, so its tiles are read (never written) from `~/.local/share/opencode/opencode*.db` with `sqlite3 -readonly` and use those recorded dollars. Public model pricing is fetched hourly (LiteLLM, models.dev, and OpenUsage's supplement). Update checks contact GitHub for the signed feed and release downloads; Sparkle system-profile reporting is disabled.
- Quota history stores only timestamps and percentages in Headroom’s own Application Support directory, bounded to the most recent hour of observations per current window. No prompts or credentials are included.
- No analytics, no crash reporting, no accounts.

## Build from source

```sh
swift test
script/build.sh            # debug → build/Headroom.app
script/build.sh release
```

To generate synthetic native layout captures without accessing real logins:

```sh
HEADROOM_UI_ARTIFACTS="$PWD/.build/ui-checks" swift test --filter IslandRenderingTests
```

These captures check native text and layout; AppKit's view capture does not reproduce the desktop glass backdrop. Verify glass appearance and VoiceOver navigation in the running app; the SwiftPM test host does not expose the full accessibility tree.

Releases are cut with `script/release.sh vX.Y.Z`, which runs the tests, builds arm64 release, signs ad-hoc, packages a DMG, tags, and publishes a GitHub Release with the matching `CHANGELOG.md` section as notes. It also signs and publishes `appcast.xml` for in-app updates. The dedicated Sparkle key lives in the release maintainer’s Keychain under account `io.github.peytonnowlin.Headroom`; never replace it casually or commit/export the private key. See [release signing](docs/release-signing.md).

## Credits

Provider adapters and spend parsing are ported from [openusage](https://github.com/robinebers/openusage); the Liquid Glass island is inspired by [tokenly](https://github.com/itsSwanks/tokenly). See `NOTICE`.

MIT licensed.
