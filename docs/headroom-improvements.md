# Headroom usability improvements

Implement the seven agreed improvements while preserving the per-display island described in ADR-0001.

1. Identify the quota window driving each ring and show its reset countdown.
2. Explain saved, stale, failing, and refreshing data directly in the expanded island.
3. Label calculated spend as estimated token value and disclose missing prices; keep provider-reported extra usage separate.
4. Add persisted per-provider warning controls, snooze through each current reset cycle, opt-in quota-return alerts, and one combined warning per window per refresh.
5. Persist bounded local quota samples. Forecast from continuous recent observations, compare against whole-window pace, and explain insufficient or variable data.
6. Provide provider-specific setup/reconnect instructions and individual retry buttons that honor cooldowns.
7. Add non-color compact status cues, descriptive accessibility labels, and motion preference support for repeating ring animations.

Validation: core tests for history retention, forecast confidence, reset boundaries, alert coalescing and suppression, freshness, and partial pricing; compile and package the macOS app; inspect representative UI states where local UI access permits.
