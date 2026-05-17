---
status: in-progress
started: 2026-05-10
last_updated: 2026-05-17
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

**Reconciled 2026-05-17.** The picture below is current; the
previous 2026-05-10 status badly understated progress.

**Workstream A — Library projections expansion: ✅ complete.** Eight
projections shipped (`Library.Views.{ContinueWatching, HeroCandidates,
RecentlyAdded, Browse, Detail, Search}`, `ReleaseTracking.Views.ComingUp`,
`WatchHistory.Views.Summary`). `Library.Progress` rebuilt as a
Pillar-2 GenServer with debounced flush, ETS reads, terminate-time
flush, and boot-time hydration. The `no_db_on_render_test`
locks per-LiveView Repo-query budgets; DB-on-render reads retired
across the LiveView surface. (Phase 3 follow-ups remain — see
*Open follow-ups* below — but they are projection-shape expansions
behind a locked-in architecture, not workstream blockers.)

**Workstream B — Acquisition split: ✅ 3 of 3 phases shipped.**
Downloads cleanly extracted to `MediaCentarr.Downloads.*` per
ADR-043 (2026-05-10). Search extraction shipped 2026-05-17 with
`Search.Criteria` as the boundary inversion. Phase 3 boundary
cleanup pruned the inflated export list 2026-05-17; the once-
vestigial `Library` dep is now load-bearing via `LibraryReconciler`
(ADR-043 amended). Optional Phase 4 (Pursuits promotion) remains
parked per ADR-043 rationale.

**Workstream C — ephemeral-field cleanup: ✅ complete.** Both
audited fields (`last_attempt_*`, `last_queue_*`) explicitly
confirmed Pillar-1 durable; rationale recorded in moduledocs.

**Workstream D — pattern documentation: ✅ complete.**
`MediaCentarr.Cache` and `MediaCentarr.Topics` moduledocs are the
canonical homes for the three-flavour Cache.Worker pattern and the
source-vs-derived PubSub taxonomy.

**Adjacent campaigns shipping pillar-aligned work:**
* **Library Schema v2** (`library-schema-v2.md`, phases 1–3 shipped
  2026-05-16) rebuilt the Pillar-1 schema the projections rebuild
  from: PlayableItem as the canonical leaf, polymorphic
  `(owner_type, owner_id)` discriminators on Image/Extra/ExternalId,
  typed Pillar-1 fields, EntityShape.normalize/3 retired. The
  Workstream-A projection set (Browse / Detail / Search / Progress)
  shipped as Phase 3 of that campaign — counted here too because
  they fulfil this campaign's "every Library LiveView read path
  through a Pillar-2 projection" criterion.
* **Library presence unification** (`done/library-presence-unification.md`,
  phases 1–2 shipped 2026-05-17) moves file-presence ownership from
  Watcher (`KnownFile`) into Library (`Library.FilePresence`),
  thinning the Watcher context toward a pure filesystem-observer
  adapter. Aligned with this campaign's pillar-segregation goal:
  durable state belongs in the Library pillar; the Watcher's
  GenServer state is Pillar 2.

**Net remaining for this campaign:** the Open follow-ups list below
(projection-shape expansions + cross-cutting items). All four
core workstreams are complete; the optional Phase 4 of Workstream B
(Pursuits promotion) stays parked.

HomeLive read paths now read entirely through projections:
- `/` hero → `Library.Views.HeroCandidates`
- `/` continue watching → `Library.Views.ContinueWatching`
- `/` recently added → `Library.Views.RecentlyAdded`
- `/` coming up → `ReleaseTracking.Views.ComingUp` (grab-status
  enrichment overlaid at read time to avoid a circular boundary
  dep against Acquisition).

LibraryLive grid: `Views.Browse` projection exists and is locked
in by `no_db_on_render_test`. Consumer-side flip from
`Library.Browser.fetch_all_typed_entries/0` to `Views.Browse` is a
Phase 3 follow-up tracked in the Library Schema v2 campaign
(requires `BrowseItem` to carry `progress`, `resume_target`,
`extra_progress`, per-card `playing?` — projection-shape
expansion).

`section_reloaders/1` no longer matches source events directly —
every reload is driven by a derived `*_view_updated` broadcast.

## The three pillars — current placement audit

The audit is the heart of the campaign — every workstream below
derives from a row in the *Misplaced* / *Missing* columns. When
the audit reads "everything correctly placed," the campaign is
done.

### Pillar 1 — Long-term (DB)

**Correctly placed (updated 2026-05-17 for Library Schema v2):**

* Library entities — containers (`library_movies`,
  `library_tv_series`, `library_movie_series`, `library_video_objects`,
  `library_seasons`, `library_episodes`), leaves
  (`library_playable_items`), supporting tables
  (`library_extras`, `library_images`, `library_external_ids`).
  All container schemas carry only metadata; no `content_url`,
  no `tmdb_id`, no `imdb_id` — those moved to `ExternalId` /
  `WatchedFile` / `PlayableItem` per Library Schema v2.
* `library_watched_files`, `library_extra_files` — file-path
  records keyed by `playable_item_id` (or extra_id). Resume
  position lives separately.
* `library_watch_progress` — resume position must survive
  restart. Pillar-1 source; Pillar-2 GenServer
  (`Library.Progress.Worker`) is the hot read path with
  debounced flush back to this table.
* `acquisition_grabs`, `acquisition_pursuits` — long-running
  async lifecycle; restart-recovery depends on durability.
* Watcher known-files table (`watcher_files`) — **slated for
  retirement** by the `library-presence-unification` campaign.
  Phase 1+2 shipped: `library_file_presences` is the new
  Library-owned source of truth; the watcher dual-writes. The
  `watcher_files` table will be dropped in Phase 7.
* `library_file_presences` — added 2026-05-17. Single source of
  truth for "we observed this file on disk at time N". Cascade-
  delete from this row will (after campaign Phase 3) remove the
  WatchedFile/ExtraFile linked to it.

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

**Correctly placed (added 2026-05-16, Library Schema v2 Phase 3):**

* `Library.Views.Browse` — ETS-backed projection of the full
  presentable entity catalog (movies, TV series, MovieSeries
  containers, standalone VideoObjects). Subscribes to
  `library:updates`. Locked in by the `no_db_on_render_test`
  budget for `/library`. LibraryLive grid consumer-side flip is
  a Phase 3 follow-up in the Library Schema v2 campaign.
* `Library.Views.Detail` — ETS-backed projection of a single
  entity's full detail tree, keyed by `PlayableItem.id`.
  Subscribes to `library:updates`. Microsecond reads at modal
  open.
* `Library.Views.Search` — in-memory entity index for text-
  filter substring matching. Subscribes to `library:updates`.
* `Library.Progress.Worker` — Pillar-2 GenServer with debounced
  5s flush. Hot read path is ETS via `Library.Progress.get/1`;
  writes via `record/3` go to ETS immediately and flush back to
  `library_watch_progress` on debounce or `terminate/2`.
  Boot-time hydration from Pillar 1 on app start. Broadcasts
  `{:progress_ticked | :progress_flushed | :progress_hydrated, _}`
  on `library:progress`. Closes the I-2 stale-read window —
  `ProgressBroadcaster` and `Library.list_in_progress/0` overlay
  in-memory progress on Pillar-1 results.

**Missing — still hits Pillar 1 on every render:**

Workstream A is complete. The `no_db_on_render_test` enforces
the budget per LiveView; any regression fails CI.

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
* `2026-05-10` — **Acquisition Downloads extraction shipped**
  (Workstream B Phase 1). Per
  [ADR-043](../decisions/architecture/2026-05-10-043-acquisition-split.md),
  qBittorrent driver + queue + health moved to
  `MediaCentarr.Downloads.*`. New boundary declared with
  `deps: [Capabilities]`; web layer + Pursuits subsystem rewired
  to the new aliases. Search extraction (Phase 2) and
  Acquisition boundary cleanup (Phase 3) remain open.
* `2026-05-16` — **Library Schema v2 phases 1–3 shipped
  ([sibling campaign](library-schema-v2.md)).** Rebuilds the
  Pillar-1 schema. PlayableItem is the canonical leaf;
  Image/Extra/ExternalId carry single
  `(owner_type, owner_id)` discriminators; container schemas
  carry only metadata. EntityShape.normalize/3 and
  WatchedFile.owner_id/1 deleted. Pillar-1 fields typed
  (`:date`, `:integer`, `Library.Person` embedded schema for
  cast/crew). Counted here because Phase 3's projection
  deliverables (Browse / Detail / Search / Progress + DB-on-
  render retirement) close Workstream A.
* `2026-05-17` — **Library presence unification phases 1–2
  shipped ([sibling campaign](done/library-presence-unification.md)).**
  `Library.FilePresence` is the new Pillar-1 source of truth for
  "we observed this file at time N"; Watcher is being thinned
  toward an observer-only role with no durable state. Backfill
  migration intentionally skips orphan KnownFile rows, healing
  the orphan-stuck-pipeline class on upgrade. Aligns
  Watcher/Library boundaries with the three-pillar audit's
  intent; campaign-internal phases 3–8 remain.
* `2026-05-17` — **Status reconciled against `jj log`.** The
  2026-05-10 status badly understated progress; reconciliation
  added Workstream A's six post-2026-05-10 deliverables (Browse,
  Detail, Search, Progress GenServer, DB-on-render retirement,
  WatchHistory baseline gap) and flagged Workstream B Phase 1
  as shipped. Reconciliation rule applied: read campaign file,
  diff against `jj log`, update before any new code touches the
  campaign.

## Workstreams

Each tagged with the pillar(s) it operates on.

### A. Library projections expansion *(Pillar 1 → Pillar 2 fan-out via Pillar 3)* — ✅ complete

Apply the ContinueWatching blueprint to remaining DB-hitting read
paths.

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
* [x] `Library.Views.Browse` — projection for the full presentable
  entity catalog. Shipped as Library Schema v2 Phase 3 Task A,
  commit `myopmstx`. *(shipped 2026-05-16)*
* [x] `Library.Views.Detail` — per-PlayableItem projection of the
  full detail tree. Shipped as LS-v2 Phase 3 Task B, commit
  `yrrtpzko`. *(shipped 2026-05-16)*
* [x] `Library.Views.Search` — in-memory entity index. Shipped as
  LS-v2 Phase 3 Task C, commit `slxsnvrq`. *(shipped 2026-05-16)*
* [x] `Library.Progress.Worker` — Pillar-2 GenServer with debounced
  flush, ETS reads, terminate-time flush, boot-time hydration.
  Closed the I-2 stale-read window. Shipped as LS-v2 Phase 3
  Task D, commit `ykzvpqqu`. *(shipped 2026-05-16)*
* [x] DB-on-render reads retired across the LiveView surface;
  `no_db_on_render_test` locks per-LiveView Repo-query budgets.
  Shipped as LS-v2 Phase 3 Task E, commit `sywypwys`.
  *(shipped 2026-05-16)*

**Closing notes:**
* Baselines for the new suites (`HeroCandidates`, `RecentlyAdded`,
  `ComingUp`) were never regenerated as the earlier
  `Next pickup` directed. Listed under *Open follow-ups* below
  rather than blocking workstream closure — the projections are
  in production and the no-DB-on-render test guards against
  regression.
* LibraryLive grid / DetailLive consumer-side flip from
  `Library.Browser.fetch_all_typed_entries/0` to `Views.Browse`
  (and the analogous Detail / Search flips) are projection-shape
  expansions deliberately deferred and tracked in the Library
  Schema v2 campaign's Phase 3 follow-ups. They don't reopen
  Workstream A — the architecture is locked in by the
  `no_db_on_render_test`; the work is "fatten the projection
  shapes" rather than "build the projection".

### B. Acquisition split — extract Downloads and Search

Decompose the 76-file `MediaCentarr.Acquisition` boundary into
three sibling contexts: a slim `Acquisition` (grab lifecycle +
Pursuits aggregate), a new `Downloads` (download-client
integration), and a new `Search` (Prowlarr-facing stateless
layer). Phased rollout, each phase independently shippable.

The workstream's original "Pillar 1 partition + Pillar 3
re-routing — separate grab/download from Library writes" framing
turned out not to match the actual code: there are no
Acquisition-to-Library writes and the schemas are already
separately namespaced. The real opportunity is the sub-context
split. See ADR-043.

* [x] Design ADR —
  [ADR-043](../decisions/architecture/2026-05-10-043-acquisition-split.md)
  proposed 2026-05-10.
* [x] Phase 1 — extract `Downloads` (qBittorrent driver, queue,
  health). 10 source files + 8 test files moved to
  `MediaCentarr.Downloads.*`; consumers across web layer +
  Pursuits subsystem rewired to new aliases; new boundary
  declared with `deps: [Capabilities]` and the cluster's modules
  re-exported. *(shipped 2026-05-10)*
* [x] Phase 2 — extract `Search` (Prowlarr, query, results, title
  matcher, quality). 10 source files + 7 test files moved to
  `MediaCentarr.Search.*`; new `Search.Criteria` struct decouples
  Search from `Acquisition.Pursuits.Recipe` (Recipe projects into
  Criteria via `to_criteria/1`). Acquisition's Boundary now declares
  `MediaCentarr.Search`; exports dropped Prowlarr/Quality/
  QueryExpander/SearchSession (callers reach through Search now).
  *(shipped 2026-05-17)*
* [x] Phase 3 — clean up Acquisition boundary. Pruned 5 unused
  exports (`Pursuits.Commands.PickTarget`, `ViewModels.NextStep`,
  `ViewModels.Recipe`, plus the `Cancel`/`ChangeTarget` confusion
  caught + restored by Boundary). The `Library` dep, originally
  flagged as vestigial, became load-bearing via `LibraryReconciler`
  (added between ADR-043 drafting and Phase 3 landing) — ADR-043
  amended with a correction note rather than forcing a removal that
  would break presence-check short-circuiting. *(shipped 2026-05-17)*
* [ ] (Optional Phase 4) — promote `Pursuits` to top-level.
  Currently parked; depth of the subtree is justified per
  ADR-039, not sprawl.

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

## Open follow-ups

Cross-cutting items surfaced during the work shipped this campaign
(or in tightly-coupled sibling campaigns) that aren't blocking the
remaining workstreams but **should be picked up before declaring
the campaign complete**. Each one is small enough that it doesn't
warrant its own workstream; collecting them here so they don't
slip.

**From Workstream A (projections):**

* **Regenerate baselines** for `HeroCandidates`, `RecentlyAdded`,
  `ComingUp`, `Browse`, `Detail`, `Search`, and the Progress
  GenServer's read path. `scripts/profile --rebaseline` against
  the current scale before campaign close so the projections have
  reference numbers locked in.
* **ContinueWatching availability gap.** The CW projection doesn't
  subscribe to `library:availability`; the direct-source handler
  `:availability_changed -> [:continue_watching]` in HomeLive's
  reloader is a workaround. Add availability subscription to the
  projection and remove the workaround.

**From Library Schema v2 sibling campaign (relevant to A's
"every read path through a projection" criterion):**

* **LibraryLive grid consumer flip** to `Library.Views.Browse`.
  Currently consumes `Library.Browser.fetch_all_typed_entries/0`
  for the rich entry shape. Requires expanding `BrowseItem` to
  carry `progress`, `progress_records`, `resume_target`,
  `extra_progress`, per-card `playing?`. `no_db_on_render_test`
  budget for `/library` is 80 queries today; target ≤5.
* **DetailLive / EntityModal consumer flip** to
  `Library.Views.Detail`. `DetailItem` needs the full file /
  season / episode tree.
* **Library search consumer flip** to `Library.Views.search/2`.
  Decision required: per-leaf rows (better UX, larger index) or
  entity-only matching (simpler, regresses nested season/episode
  substring match). Wait on user-behaviour data, not a guess.
* **ADR for PlayableItem reification** (Library Schema v2
  completion criterion). The campaign moduledoc is acting as the
  record; promote to a real ADR alongside ADR-029
  data-decoupling.
* **`Cache.handle_message/1` partial-refresh direct test**
  (LS-v2 Phase 3 Task B review I-1). The callback is exercised
  end-to-end via Detail tests but lacks a unit test in
  `cache_test.exs`.
* **`Library.playable_item_ids_for_entities/1` UNION**
  (LS-v2 Phase 3 Task B review I-2). Collapse three sequential
  `Repo.all/1` calls into one UNION when batched cascade ops
  surface as a hot path.

**From v0.62.3 (Library empty-state scan UX):**

* **Lift the inline pipeline-activity indicator into a shared
  component.** Today it lives in LibraryLive's empty state; if
  the UX hypothesis proves valuable, extract for use on Home /
  Settings / setup-tour summary.
* **Telemetry-driven push updates** instead of the 1s
  `Pipeline.Stats` poll. Matches future move toward
  PubSub-driven view updates; current 1s tick is fine.
* **Per-stage breakdown** (parse / search / images / publish)
  in the activity indicator. One aggregate count is enough
  today; the breakdown is useful when a stage gets stuck.

**From v0.63.0 (Library presence unification Phase 1+2):**

* **Phases 3–8** of `library-presence-unification` (FK on
  WatchedFile/ExtraFile, read-site flip, DiscoveryProducer ETS
  dedup, AbsenceSweeper port, KnownFile retirement, doc
  updates). Tracked in that campaign file; mentioned here so
  the desktop-rearchitecture closer can verify that campaign
  has progressed before declaring this one done.

**From the reconciliation itself:**

* **Update `docs/architecture.md` ownership table** when this
  campaign closes — reflect that Watcher owns no durable state,
  Library owns file presence, and Library.Progress.Worker is
  the canonical Pillar-2 GenServer example.
* **Storybook coverage for the new projection-driven UIs**
  (Browse / Detail consumers) once those flips ship. The
  storybook contract Credo rule (MC0009) will catch missing
  stories at precommit time, but the variation matrix should be
  reviewed proactively.

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
* Pillar-1 schema redesign (PlayableItem reification, polymorphic
  discriminators, container metadata cleanup). Shipped under
  the [`library-schema-v2`](library-schema-v2.md) sibling
  campaign; this campaign reconciles against its outcome rather
  than driving it.
* Watcher / KnownFile schema retirement. Tracked under the
  [`library-presence-unification`](done/library-presence-unification.md)
  sibling campaign.

## Pointers

* [ADR-041 — In-memory projection architecture](../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md)
* [ADR-042 — Multi-session campaigns convention](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
* [ADR-043 — Acquisition split](../decisions/architecture/2026-05-10-043-acquisition-split.md)
* [ADR-045 — File-presence ownership](../decisions/architecture/2026-05-17-045-file-presence-ownership.md)
* Sibling campaigns:
  * [`library-schema-v2.md`](library-schema-v2.md) — Pillar-1
    schema redesign; phases 1–3 shipped.
  * [`done/library-presence-unification.md`](done/library-presence-unification.md)
    — Watcher-to-Library presence ownership shift; phases 1–2
    shipped.
* `lib/media_centarr/cache.ex` + `lib/media_centarr/cache/` —
  Cache.Worker behaviour and worker module.
* `lib/media_centarr/library/views/continue_watching.ex` —
  canonical projection example.
* `lib/media_centarr/library/progress.ex` +
  `lib/media_centarr/library/progress/worker.ex` — canonical
  Pillar-2 GenServer-with-debounced-flush example.
* `lib/media_centarr/topics.ex` — PubSub topic registry.
* `lib/media_centarr/profile/` — Bench, Mounts, Diff, RunData,
  Reporter (validation rig).
* `priv/profiling/` — baselines + workflow README.
* `lib/mix/tasks/profile.ex` — orchestrator with `--rebaseline`.
* `test/media_centarr_web/no_db_on_render_test.exs` —
  per-LiveView Repo-query budget guard.

The user-local plan file at
`~/.claude/plans/can-we-build-a-federated-rocket.md` is the
session-level scratchpad. This campaign supersedes it as the
durable source of truth — reconcile against the campaign file,
not the plan file.
