---
status: in progress
started: 2026-07-18
last_updated: 2026-07-18
---

# Instant, flash-free navigation

## Goal

Every page navigation paints complete, current content in one motion — no
empty-then-filled flash, no image pop-in, no perceptible delay. Organizing
principle: **a navigation never computes — it renders state that was already
prepared.** Three layers must each be ready before the click:

1. **Data** — event-updated read models (`MediaCentaur.Cache` projections);
   the click path contains no DB/GenServer/network calls.
2. **Wire** — navigation payload is O(first screen), not O(dataset).
3. **Pixels** — first-screen artwork already in the browser cache.

This finishes the commitment the codebase already made (ADR-041 projections,
ADR-051 synchronous first paint, ADR-057 deriver model). HomeLive is the
existence proof: pure projection reads, fastest page.

## Measured baseline (2026-07-18, headless Chromium vs dev :2160, warm nav)

| Page | click→painted | WS payload | server work |
|---|---|---|---|
| `/` | ~55ms | 49KB | <1ms |
| `/library` | ~64ms (first visit 243–555ms: sync poster decode) | 44KB | ~10ms |
| `/reconcile`, `/review` | ~46–68ms | 18KB | <1ms |
| `/incoming` | ~91ms | 42KB | 18ms |
| `/settings` | ~92ms | 43KB | 26ms |
| `/status` | ~112ms | 22KB | 53ms (mount) |
| `/history` | ~122ms | **276KB** | ~7ms (104ms client patch task) |

Mechanism: server replies in ~2ms; time is payload decode + full-page
morphdom patch. Cold launch: complete HTML at ~50ms, no visible WS-connect
flash. Measurement harness: session scratchpad `nav-measure2.js` (chromium-probe
IIFE — click nav link, time phx:page-loading-stop, double-rAF paint, WS bytes,
longtasks). Re-create from this description if lost; re-run after each phase.

## Phases

1. **Status projection + lifecycle convergence** — `Status.Views.Overview` +
   `Status.Views.Storage` ETS projections (Cache behaviour, new
   `status:views` derived topic); `Cache.Worker` gains optional
   `refresh_interval_ms` + `prime: :async` (sleeping-drive `df` must never
   block boot). StatusLive converges to the standard un-gated
   `ensure_loaded`-in-`handle_params` shape: dead render complete, async
   pops eliminated. `mark_seen` stays connected-only.
2. **/history payload diet** — stream events + `temporary_assigns`; render
   only the active heatmap variant. 276KB → ~40KB.
3. **Shell badge projection** — diagnostics/review/mapping counts cached;
   on_mount hooks become reads (they already subscribe to the
   invalidation topics).
4. **Artwork warmup** — idle-time prefetch of first-screen derivatives for
   main destinations; ADR-012 eager/sync stays.
5. **Console batch broadcast** — `{:log_entries, [...]}` ~100ms flush
   replaces per-line broadcasts.
6. **Acquisition read model** — de-dupes IncomingLive `build_view` +
   HomeLive `coming_up` status reads. *Droppable — measure after P5 first.*
7. **Settings probe caches** — systemd `service_state`,
   `missing_images_summary`. *Small; only if P1–5 leave /settings visible.*
8. **Reconcile spine precompute at event time** — TMDB assembly moves from
   view time to when the awaiting item appears. *Deferred; only bites with
   pending reconciliation.*
9. **Guide chapter precompile at boot.** *Trivial; fold into any phase.*

## Decisions made

- Stale-first rejected by owner: first paint must be current. Event-driven
  projections satisfy this (they update on change, not TTL).
- `assign_async`-everywhere rejected: institutionalizes the flash this
  campaign exists to remove.
- LibraryLive's dual grid representation (stream + full `entries` assign)
  kept deliberately — `entries` is the filter/sort source.
- Storage measurements are inherently periodic (existing 5-min cadence);
  serving the last measurement instantly is not a staleness regression —
  today the user stares at empty tiles until `df` returns.

## Status

- **Phase 1 ✅ 2026-07-18.** `Cache.Worker` gained `refresh_interval_ms` +
  `prime: :async`; `Status.Views.Overview`/`Storage` projections shipped
  (`status:views` topic); StatusLive converged to un-gated
  `ensure_loaded`-in-`handle_params`. Measured: /status warm nav 112→~75ms,
  zero async pops, dead render complete (verified live), and the 1s
  `File.dir?`-per-media-dir poll while the page was open is gone.
  Deferred observation: `dir_health` (filesystem truth) deliberately
  overlaps `Availability.dir_status/0` (watcher truth) — unify only as
  part of an Availability-owned redesign, see
  `Status.Views.StorageSnapshot` moduledoc.

- **Phase 2 ✅ 2026-07-18.** /history payload 276KB → ~78KB, warm nav
  122→~53ms, no long tasks. Scope revision vs the plan: the events list
  was already paginated at 50 (streams/`temporary_assigns` unnecessary) —
  the real weight was the 4 pre-rendered heatmap variants (~1,460
  `<rect>`s). Now only the active variant renders (the type filter's
  existing round-trip swaps it), fills are CSS classes (`.hm-fill-*`)
  instead of inline color-mix strings, and zero-count cells ship no
  tooltip/click attrs. Real-browser verified (probe gotcha: wait for
  `phx-connected` on `[data-phx-main]`, not `liveSocket.isConnected()`,
  before synthetic clicks — pre-join clicks are silently dropped).

## Next steps

- Phase 3: shell badge projection (diagnostics/review/mapping counts).

## Completion criteria

- Re-run of the nav harness: every page ≤ ~70ms click→painted warm, no
  payload > ~60KB, no long task > 50ms during nav, zero async content pops
  on /status, no paint blocked on image decode after warmup.
- No DB/GenServer/network call on any page's navigation path except
  projection/ETS/persistent_term reads (phases 6–8 close stragglers or
  record explicit acceptance).
- Wiki/docs untouched (internal performance work; no user-visible surface
  change beyond speed).
