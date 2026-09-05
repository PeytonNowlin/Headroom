# Headroom: updates, notifications, trends, keyboard access, and idle work

Implement the five agreed improvements while keeping the island on every display by default.

1. Integrate Sparkle with explicit Check for Updates and optional automatic checks. Embed the framework correctly, sign update archives with a dedicated Keychain-held Ed25519 key, and generate a GitHub-hosted appcast during release packaging.
2. Offer opt-in macOS notifications using the existing quota alert policy. Include open-provider and snooze actions, request permission only when enabled, and retain island banners if notifications are unavailable.
3. Add seven- and thirty-day estimated token-value charts and model attribution, using the existing local ledgers and pricing. Distinguish missing observations and incomplete pricing from zero usage.
4. Let the global shortcut focus the island on the active display, navigate providers with arrow keys, activate with Return, traverse controls with Tab, and close with Escape. Preserve non-activating hover behavior and provide accessible labels and focus.
5. Use fast countdown ticks only while a detail/expanded island or settings is visible. Avoid rewriting unchanged spend caches, coalesce overlapping scans, and measure idle work before and after.

Validate with focused core and app tests, native view captures, an optimized packaged build, an isolated signed updater feed, keyboard interaction checks, and sampled idle CPU/wakeup evidence. Keep notification permission and VoiceOver verification limits explicit if the OS denies automation.

## Validation

- 88 tests passed, including DST/calendar windows, missing prices, per-model totals, unchanged scan I/O, provider removal, keyboard focus state, preference migration, and native layout captures.
- Optimized arm64 bundle passes resource, framework-linkage, runtime-path, and deep code-signature checks.
- An isolated native SPUUpdater host discovered signed v0.4.0 metadata and rejected a modified feed. Sparkle’s signature tool accepted the archive and rejected modified archive bytes. The isolated probe did not perform an installation/relaunch.
- Live macOS automation exercised the global shortcut, arrows, Return into provider details, opening Trends, and Escape restoring the previous app. Accessible native controls were present. Spoken VoiceOver output and opt-in Notification Center delivery remain manual checks; notification permission was not enabled automatically.
- A 30-second installed-app sample recorded 0.01 CPU-seconds versus 0.74 in the earlier sample. RSS was approximately 132 MiB versus 112 MiB. These short, separately timed samples are diagnostic observations, not a controlled benchmark.
- Synthetic captures verify layout with non-private sample data. macOS did not allow capturing the live window image; they do not verify desktop glass composition.
