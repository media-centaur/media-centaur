---
status: accepted
date: 2026-03-05
---
# Human-readable durations

## Context and Problem Statement

Entity durations are stored as ISO 8601 strings (`"PT3H48M"`, `"PT1H24M"`) per schema.org's `duration` property. The library LiveView renders these raw strings directly next to the clock icon in episode and movie detail rows. ISO 8601 duration format is a machine-readable encoding — no media application displays runtimes this way. Users expect the industry-standard format used by TMDB, IMDb, Plex, and streaming services: `3h 48m` or `1h 24m` for multi-hour durations, and `45m` for sub-hour durations.

## Decision Outcome

Chosen option: "format ISO 8601 durations as `Xh Ym`", because this is the universal convention in media applications and is immediately scannable.

Display rules:

1. **Hours and minutes:** `3h 48m` — space-separated, no leading zeros, no seconds.
2. **Sub-hour:** `45m` — omit the hours component entirely.
3. **Even hours:** `2h` or `2h 0m` — either is acceptable; prefer `2h 0m` for consistency with the general format.
4. **Nil/missing:** render nothing (the `:if` guard already handles this).

The conversion happens at the display layer (a helper function in `LiveHelpers`) — the stored value remains ISO 8601 per schema.org and the data format spec.

### Consequences

* Good, because durations are instantly readable without mental parsing
* Good, because the format matches every major media application users already know
* Good, because the storage format (ISO 8601) is preserved — only the display changes
* Bad, because a display helper must parse the ISO 8601 string; mitigated by the format being trivially regular (`PTxHyM`)
