# Playback Status Enrichment — Design

**Date:** 2026-06-09
**Status:** Approved (design), pending implementation plan

## Problem

The status page's playback Activity widget (`MediaCentaurWeb.ActivityWidgetComponents.playback_widget/1`) is the one subsystem tile that goes blank at rest. When a session is live it shows now-playing title, state, progress, and time remaining; when nothing is playing — the common case — it renders only **"Idle."**

Every other recently-enriched tile tells a *narrative even at rest*: the TMDB tile shows `Last enriched 4m ago · 12 this session` plus a recent-enrichment list; the Watcher tile shows last scan / settling / failure reasons. Playback should match that bar.

This serves the app's enthusiast / homelab-operator persona (recorded in auto-memory `project-status-page-persona`): someone who wants to *watch the subsystems working and prove they're healthy*, not just confirm playback plays. They asked for three things on this tile: a **watch narrative**, **plumbing health**, and **lifetime stats**.

## Honesty constraint (shapes the design)

The mpv IPC link is **per-session**: `MediaCentaur.Playback.MpvSession` is a GenServer that owns one Unix-domain socket for the duration of one playback. There is **no persistent playback daemon** to ping when idle. Therefore "plumbing health at rest" must NOT fabricate a heartbeat. The truthful at-rest proof-of-life is the **timestamp of the most recent recorded progress** — evidence the whole record path (mpv → session → persist → broadcast) worked, and how recently. Live link health (socket connected, position advancing) is only shown while a session exists.

## Design — one widget, three always-present bands

The widget keeps its single-card shell. Three stacked bands, each adapting its content to playback state. All three are always rendered (consistent tile shape every visit).

### Band 1 — Now / Recently (narrative)

- **Playing:** unchanged from today — one block per active session: state pill, title, progress bar, time remaining.
- **Idle:** replace the bare "Idle" with `Last watched {title} · {time_ago}` followed by a recent-watched list of 3–5 rows. Row shape mirrors the TMDB recent-enrichment list: `{kind label} · {title} · {time_ago}`, newest first.
- **Source:** `MediaCentaur.WatchHistory.recent_events/1` (returns `Event` records with `completed_at`, `duration_seconds`, `type`, entity association). No render-time query — `StatusLive` loads it into assigns (per the ActivityWidgets contract: widgets receive a data bundle, never query).

### Band 2 — Plumbing health (honest, state-aware, carries the only state color)

- **Playing:** `link connected · position advancing` derived from the live `MpvSession` snapshot (socket present, position moving). Turns to a warning/error color if a session exists but the socket has dropped or position is frozen.
- **Idle:** `Recorder ready · last write {time_ago}` — from the newest `WatchEvent.completed_at`. If there is *no* watch history at all, `Recorder ready · no writes yet` (neutral, not an error).
- This is the only band that uses color; bands 1 and 3 stay neutral (reserve color for health/severity per the no-chip-palette rule).

### Band 3 — Lifetime stats (flex, neutral)

- A single stat line: `{hours} watched · {titles} completed · {streak}-day streak`.
- **Source:** `MediaCentaur.WatchHistory.stats/0` → `total_seconds`, `total_count`, `streak`. (Cheap DB aggregates; no result-set growth.)
- **No heatmap** — explicitly cut as not interesting enough to earn the space/component.

## Data flow

`StatusLive.mount/3` and its live-update handlers already assemble the playback bundle. Extend the bundle (in `build_playback_state/0` and on relevant PubSub updates) with:

- `recent_watches` — `WatchHistory.recent_events(5)` (band 1 idle)
- `last_write_at` — newest `completed_at` (band 2 idle); can be derived from `recent_watches` head to avoid a second query
- `lifetime` — `WatchHistory.stats/0` (band 3)
- live `MpvSession` snapshot fields for the active session(s) (band 2 playing) — confirm what `MpvSession`'s read-only snapshot already exposes (`socket` presence, `position`) during planning.

Refresh cadence: lifetime stats and recent-watches need only refresh on `watch_history` PubSub events and on mount — not on every progress tick. Plumbing-health "last write" follows the same signal.

## What this is NOT

- Not a "Continue Watching / resume shortlist" — that's a browse-UI job, deliberately out of scope for the health board.
- Not a new heatmap component.
- Not a fabricated idle heartbeat.

## Testing

- `HealthBoard` / widget render is pinned by the storybook story for `playback_widget` (MC0009) — update the story's variation matrix to cover: idle-with-history, idle-no-history, playing-link-healthy, playing-link-degraded.
- Widget is a pure function component over a data bundle — unit-renderable in isolation with fixtures (no PubSub, no DB).
- Live-wiring (assign updates on `watch_history` events, idle↔playing transitions) belongs in `status_live_test.exs`, not the story.
- Test/fixture titles use generic placeholders / PD-CC only.

## Open items for planning

- Confirm the exact read-only snapshot fields `MpvSession` exposes for band 2 "playing" health.
- Decide whether `last_write_at` is derived from `recent_events` head or a dedicated aggregate.
- Story variation matrix wiring (MC0009 migration tax — bundle component + story in one change).
