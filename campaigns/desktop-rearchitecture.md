---
status: in-progress
started: 2026-05-10
last_updated: 2026-05-10
---
# Local-only desktop rearchitecture

## Goal

Move media-centarr-app away from Phoenix-web defaults toward a
**local-only, single-user, no-auth desktop application** paradigm.
Statefulness is no longer a liability to scale around — it is an
asset to lean on.

The organising principle is **three-pillar segregation**, from
[ADR-041](../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md).
Every piece of state in the codebase is explicitly assigned to
exactly one pillar:

1. **Long-term storage (DB)** — source of truth for state that
   *must* survive a restart. Library entities, watch progress,
   acquisition lifecycle, watcher known-files.
2. **Short-term storage (in-memory)** — ETS, `:persistent_term`,
   or GenServer state for state that is either *derivable from
   long-term storage* (projections, caches) or *runtime-only by
   nature* (mpv session, rate-limiter window, queue poll
   snapshot).
3. **Real-time communications (PubSub)** — choreography between
   pillars 1 and 2. Source-of-truth contexts emit canonical
   events; projections subscribe and emit derived
   `*_view_updated` events; LiveViews subscribe to the derived
   topics.

Misplaced state — durable things in memory, ephemeral things in
the DB, or LiveViews subscribed directly to raw source events
instead of derived view events — is the primary defect class
this campaign exists to fix.

## Status

Foundation laid: ADR-041, the three-pillar pattern now proven across
**four** projections (Library.Views.ContinueWatching, HeroCandidates,
RecentlyAdded, ReleaseTracking.Views.ComingUp); profiling rig in
place with baseline diffing and `--rebaseline`; Settings,
Capabilities, Controls all paradigm-correct. Multi-user audit
confirms zero vestigial patterns. **Workstream A is one projection
short of complete** — WatchHistory views remain. Acquisition split
(B), ephemeral-field cleanup (C), and pattern-doc consolidation (D)
unstarted. No active blockers.

HomeLive read paths now read entirely through projections:
- `/` hero → `Library.Views.HeroCandidates`
- `/` continue watching → `Library.Views.ContinueWatching`
- `/` recently added → `Library.Views.RecentlyAdded`
- `/` coming up → `ReleaseTracking.Views.ComingUp` (grab-status
  enrichment overlaid at read time to avoid a circular boundary
  dep against Acquisition).

`section_reloaders/1` no longer matches source events directly —
every reload is driven by a derived `*_view_updated` broadcast.

## The three pillars — current placement audit

The audit is the heart of the campaign — every workstream below
derives from a row in the *Misplaced* / *Missing* columns. When
the audit reads "everything correctly placed," the campaign is
done.

### Pillar 1 — Long-term (DB)

**Correctly placed:**

* Library entities (`movies`, `tv_series`, `seasons`, `episodes`,
  `extras`, `images`, `identifiers`, `linked_files`,
  `pending_files`).
* `library_watch_progress` — resume position must survive
  restart.
* `acquisition_grabs`, `acquisition_pursuits` — long-running
  async lifecycle; restart-recovery depends on durability.
* Watcher known-files table.

**Audited and confirmed Pillar-1 durable (Workstream C, 2026-05-10):**

* `acquisition_grabs.last_attempt_outcome` /
  `acquisition_grabs.last_attempt_at` — diagnostic-only, but durable
  for post-restart UX continuity on a single-user app (see
  Workstream C audit + `Grab` moduledoc).
* `acquisition_pursuits.last_queue_state` /
  `acquisition_pursuits.last_queue_health` — decision-influencing
  (drives lifecycle transition detection in
  `Pursuits.Observations.derive_transition_event/3`); restart-loss
  would spuriously fire `DownloadStarted`. See `Pursuit` moduledoc.

### Pillar 2 — Short-term (in-memory)

**Correctly placed:**

* `Library.Views.ContinueWatching` — ETS + Cache.Worker
  projection.
* `Settings`, `Capabilities`, `Controls` — `:persistent_term` +
  Cache.Worker singleton caches.
* `SpoilerFree` — routes through Settings (no separate cache;
  the unified container).
* `Playback.MpvSession` — GenServer with debounced Pillar-1
  writes.
* `Acquisition.SearchSession` — GenServer for transient UX
  state.
* `Acquisition.QueueMonitor` — `:persistent_term` + GenServer
  for poll snapshot + history.
* `TMDB.RateLimiter` — GenServer (sliding window).
* `TMDB.Client` — `:persistent_term` (built `Req` client).

**Correctly placed (added 2026-05-10):**

* `Library.Views.HeroCandidates` — ETS-backed projection of
  `list_hero_candidates/1`. Subscribes to `library:updates` +
  `library:availability`; broadcasts `:library_view_updated, :hero_candidates`.
* `Library.Views.RecentlyAdded` — ETS-backed projection of
  `list_recently_added/1`. Same subscriptions; broadcasts
  `:library_view_updated, :recently_added`.
* `ReleaseTracking.Views.ComingUp` — ETS-backed projection of
  `list_releases_between/3`. Subscribes to `release_tracking:updates`;
  broadcasts `:release_tracking_view_updated, :coming_up` on a new
  `release_tracking:views` topic. Caches today..today+365; reads
  filter the requested window in-memory. Grab-status enrichment is
  read-time-only (HomeLive overlays Acquisition data) — keeps the
  projection inside the ReleaseTracking boundary.

  Added 2026-05-10b:

* `WatchHistory.Views.Summary` — `:persistent_term`-backed projection
  bundling stats, heatmap cells per type, and per-type rewatch
  counts into one snapshot. Subscribes to `watch_history:events`
  (now carrying both `:watch_event_created` and `:watch_event_deleted`).
  Broadcasts `:watch_history_view_updated, :summary` on
  `watch_history:views`.

**Missing — still hits Pillar 1 on every render:**

Workstream A is complete. No remaining DB-on-render entries.

### Pillar 3 — Real-time (PubSub)

**Correctly placed:**

* All topics in `lib/media_centarr/topics.ex` are global, no
  per-user scoping (multi-user audit confirmed).
* ContinueWatching projection follows the
  *subscribe-canonical-emit-derived* pattern: subscribes to
  `library:updates` / `watch_history:events` /
  `playback:events`, broadcasts
  `{:library_view_updated, :continue_watching}` on
  `library:views`.

**Hygiene to enforce going forward (Workstream D):**

* New projections must follow the same pattern. LiveViews should
  subscribe to derived `*_view_updated` topics, *not* to the raw
  source events.
* The pattern itself is currently described inside individual
  moduledocs; it should land in one canonical place.

## Decisions made

Append-only.

* `2026-05-10` — **Three-pillar segregation is the organising
  principle.** Every state-bearing module belongs to exactly one
  pillar; cross-pillar coordination uses Pillar 3.
  ([ADR-041](../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md))
* `2026-05-10` — Cache.Worker (`lib/media_centarr/cache.ex`) is
  the unified container for Pillar 2 — one behaviour, three
  flavours (ETS for per-view result sets, `:persistent_term` for
  tiny-but-hot global config, GenServer for purely transient
  runtime state).
* `2026-05-10` — First Pillar-2 projection scoped to the Continue
  Watching read path on HomeLive. Validates the pattern before
  fan-out. (commits `optyzrps`, `wzplrrwo`)
* `2026-05-10` — Settings table cached in `:persistent_term`,
  dropping the earlier SpoilerFree-specific cache. Confirms
  `:persistent_term` for tiny-but-hot config; ETS for per-view
  result sets. (commit `nnrtqpoo`)
* `2026-05-10` — Built the profiling rig *before* extending the
  pattern. Without measurement, "this projection is fast" is
  folklore. (commits `pxryktqs`, `uoosxwnq`, `xyrzxmup`)
* `2026-05-10` — JSON-canonical baseline format; markdown is a
  rendering of the same `RunData` struct so the two cannot
  drift. `baseline-<scale>.{md,json}` tracked,
  `runs/<ISO8601>.{md,json}` gitignored.
* `2026-05-10` — `--rebaseline` flag uses `Mix.shell().yes?` with
  `default: :no` so destructive promotion is opt-in and CI cannot
  rebaseline accidentally.
* `2026-05-10` — **Multi-user audit closed: codebase is
  paradigm-clean.** Zero `%Scope{}` plumbing, no auth modules,
  no per-user PubSub topics, no `belongs_to :user` on any
  schema. Recorded so future contributors don't re-audit.
* `2026-05-10` — `Playback.MpvSession` already paradigm-correct
  (Pillar 2 GenServer with debounced Pillar-1 writes). Not a
  future workstream — the original 7-step plan's "Playback
  session GenServer" item was already satisfied.
* `2026-05-10` — UI ephemeral state (open drawer, current zone,
  current filter) lives in LiveView socket assigns and is
  correctly placed. No "UIState" workstream needed.
* `2026-05-10` — **HeroCandidates / RecentlyAdded shipped.**
  Both subscribe to `library:updates` + `library:availability`
  (the existing ContinueWatching projection has a known gap on
  availability subscriptions — left in place for now, see
  Workstream A's WatchHistory note).
* `2026-05-10` — **ComingUp shipped on its own topic.** New
  `release_tracking:views` topic + `Topics.release_tracking_views/0`.
  Per-context derived topics scale better than a single
  `views:updates` firehose; the LiveView subscribes once per
  consumed context.
* `2026-05-10` — **Grab-status enrichment stays at read time.**
  Acquisition depends on ReleaseTracking; pulling the enrichment
  into the projection would force a back-dep cycle. HomeLive
  composes `Acquisition.statuses_for_releases/1` over the cached
  release list — same cost as before for the Acquisition
  query, but the 2 release-tracking queries per render are gone.
* `2026-05-10` — **Section reloaders are now projection-only.**
  `section_reloaders/1` no longer pattern-matches source events
  (`:entities_changed`, `:releases_updated`, `:item_removed`,
  `:release_ready`, `:watch_event_created`,
  `:entity_progress_updated`). Every reload is driven by a
  derived `*_view_updated` broadcast. The remaining direct-source
  handler (`:availability_changed -> [:continue_watching]`)
  exists because the ContinueWatching projection doesn't
  subscribe to availability — see the gap noted above.

## Workstreams

Each tagged with the pillar(s) it operates on.

### A. Library projections expansion *(Pillar 1 → Pillar 2 fan-out via Pillar 3)*

Apply the ContinueWatching blueprint to the remaining DB-hitting
read paths on HomeLive, then move on to WatchHistory.

* [x] `Library.Views.HeroCandidates` — projection for
  `list_hero_candidates/1`. *(shipped 2026-05-10)*
* [x] `Library.Views.RecentlyAdded` — projection for
  `list_recently_added/1`. *(shipped 2026-05-10)*
* [x] `ReleaseTracking.Views.ComingUp` — projection for
  `list_releases_between/3`. New `release_tracking:views` topic +
  `:release_tracking_view_updated` discriminator. *(shipped 2026-05-10)*
* [x] `WatchHistory.Views.*` — `Summary` projection
  (`:persistent_term` flavour) bundling the History page's three
  aggregate reads (`stats/0`, `heatmap_cells_by_type/0`, per-type
  `rewatch_count_map/1`) into one snapshot. New
  `watch_history:views` topic carrying
  `{:watch_history_view_updated, :summary}`. Side fix: added
  `:watch_event_deleted` broadcast to `delete_event!/1` (the
  projection needed it for invalidation; the prior LiveView
  recomputed locally via a Task). *(shipped 2026-05-10)*

Each ships with a Suite under
`lib/media_centarr/profile/suites/`. Validate via baseline diff
before considering done.

> **Next pickup:** baselines for the three new suites
> (`HeroCandidates`, `RecentlyAdded`, `ComingUp`) were not regenerated
> as part of these commits. Run `scripts/profile --rebaseline` against
> the current scale before declaring Workstream A done so the new
> suites have reference numbers.

### B. Acquisition split *(Pillar 1 partition + Pillar 3 re-routing)*

Separate the grab/download path from Library writes — bigger
architectural lift than a projection. Wants a fresh design pass
(likely a new ADR) before code. Open questions: where does the
boundary fall, what's the new context name, what canonical
events does the split emit?

* [ ] Design ADR.
* [ ] Implementation.

### C. Pillar 1 → Pillar 2 ephemeral-field cleanup

Confirm whether grey-area fields are diagnostic-only; if so,
move them out of the DB.

* [x] Audit `acquisition_grabs.last_attempt_outcome` /
  `last_attempt_at`. **Finding:** diagnostic-only — sole production
  read is `activity_logic.last_attempt_summary/1` for display, plus
  a reset-to-nil in `Acquisition.rearm/1`. No retry or scheduling
  decision reads them. **Decision: keep in Pillar 1.** The
  completion criteria allow "explicitly confirmed Pillar-1
  durable"; post-restart UX continuity ("last attempt: no_results ·
  5 min ago") is the durability justification on a single-user
  desktop app that restarts for in-place updates. Moving them
  in-memory would wipe attempt context on every update install —
  a real UX regression for marginal architectural cleanup. The
  Grab moduledoc carries the rationale. *(audit 2026-05-10)*
* [x] Audit `acquisition_pursuits.last_queue_state` /
  `last_queue_health`. **Finding:** decision-influencing — read in
  `Observations.derive_transition_event/3` to detect lifecycle
  transitions across ticks, driving `DownloadStarted` and
  `HealthChanged` event emission. Moving in-memory would cause
  spurious `DownloadStarted` events after restart (the next tick
  would see `from == nil`, `to == "downloading"` and fire as if it
  were a fresh start). **Decision: keep in Pillar 1, durable.**
  The Pursuit moduledoc carries the rationale. *(audit 2026-05-10)*
* [x] Schema migration: not needed — neither field moved.
  *(2026-05-10)*

### D. Pattern documentation hygiene *(Pillar 2 + 3 docs)*

The Cache.Worker three-flavours pattern and the
*subscribe-canonical-emit-derived* PubSub convention are
currently scattered across several moduledocs. Consolidate so a
new contributor (or fresh agent context) finds the pattern in
one place.

* [x] Centralise the three-flavour Cache.Worker pattern in
  `MediaCentarr.Cache` moduledoc — table of flavours with
  decision criteria, misplacement defects, canonical examples,
  the source-vs-derived PubSub rule, and the test-mode fallback.
  *(shipped 2026-05-10)*
* [x] Centralise the PubSub topic taxonomy in
  `MediaCentarr.Topics` moduledoc — every topic tabulated by
  role (source / derived / coordination), owner, and payloads.
  Discipline rules: topics live in `Topics`, not inline; LiveViews
  consume derived topics, not source topics for cache-driven
  data. Side fix: `library:availability` was hardcoded in
  `Library.Availability`; promoted to `Topics.library_availability/0`.
  *(shipped 2026-05-10)*

## Completion criteria

* Every state-bearing module in the codebase is assignable to
  exactly one pillar; the pillar audit above is complete and
  accurate (no rows in *Missing* / *Possibly misplaced*).
* Every HomeLive read path either has a Pillar-2 projection or
  has a documented reason it doesn't need one.
* WatchHistory projection shipped + baseline diff stable across
  three consecutive runs.
* Acquisition split design lands as an ADR (whether or not the
  implementation follows immediately).
* `last_attempt_*` / `last_queue_*` resolved (moved to Pillar 2
  or explicitly confirmed Pillar-1 durable).
* The Cache.Worker pattern + PubSub taxonomy are documented in
  one canonical place.

## Out of scope

* Page redistribution (Library → Home + Library + Upcoming +
  History; sidebar Watch/System groups). UX/IA refactor — its
  own campaign.
* Component contracts via structs. Engineering convention — its
  own campaign.
* Auth / multi-user / scopes — confirmed already clean, no work.
* `MpvSession` refactoring — already paradigm-correct.
* TMDB rate-limiter / client — already paradigm-correct.

## Pointers

* [ADR-041 — In-memory projection architecture](../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md)
* [ADR-042 — Multi-session campaigns convention](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
* `lib/media_centarr/cache.ex` + `lib/media_centarr/cache/` —
  Cache.Worker behaviour and worker module.
* `lib/media_centarr/library/views/continue_watching.ex` —
  canonical projection example.
* `lib/media_centarr/topics.ex` — PubSub topic registry.
* `lib/media_centarr/profile/` — Bench, Mounts, Diff, RunData,
  Reporter (validation rig).
* `priv/profiling/` — baselines + workflow README.
* `lib/mix/tasks/profile.ex` — orchestrator with `--rebaseline`.

The user-local plan file at
`~/.claude/plans/can-we-build-a-federated-rocket.md` is the
session-level scratchpad. This campaign supersedes it as the
durable source of truth — reconcile against the campaign file,
not the plan file.
