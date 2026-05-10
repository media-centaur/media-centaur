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

Foundation laid: ADR-041, the three-pillar pattern proven on
Library (ContinueWatching projection), Settings, Capabilities,
and Controls; profiling rig in place with baseline diffing and
`--rebaseline`. Multi-user audit confirms zero vestigial
patterns. Three projection candidates remain on HomeLive plus
the Acquisition split. No active blockers.

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

**Possibly misplaced (see Workstream C):**

* `acquisition_grabs.last_attempt_outcome`,
  `acquisition_grabs.last_attempt_at` — may be diagnostic-only.
* `acquisition_pursuits.last_queue_state`,
  `acquisition_pursuits.last_queue_health` — may be display-only
  observables.

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

**Missing — still hits Pillar 1 on every render (Workstream A):**

* `HomeLive` hero candidates → `Library.list_hero_candidates/1`.
* `HomeLive` recently added → `Library.list_recently_added/1`.
* `HomeLive` coming up → `ReleaseTracking.list_releases_between/3`.
* `WatchHistory` reads (route + context TBD in workstream).

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

## Workstreams

Each tagged with the pillar(s) it operates on.

### A. Library projections expansion *(Pillar 1 → Pillar 2 fan-out via Pillar 3)*

Apply the ContinueWatching blueprint to the remaining DB-hitting
read paths on HomeLive, then move on to WatchHistory.

* [ ] `Library.Views.HeroCandidates` — projection for
  `list_hero_candidates/1`.
* [ ] `Library.Views.RecentlyAdded` — projection for
  `list_recently_added/1`.
* [ ] `ReleaseTracking.Views.ComingUp` — projection for
  `list_releases_between/3` (note: new context, may need its
  own `*_view_updated` topic).
* [ ] `WatchHistory.Views.*` — design + ship the WatchHistory
  projection(s); shape TBD until route is firmed up.

Each ships with a Suite under
`lib/media_centarr/profile/suites/`. Validate via baseline diff
before considering done.

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

* [ ] Audit usages of
  `acquisition_grabs.last_attempt_outcome` /
  `last_attempt_at`. If only read for diagnostics: move to
  in-memory ring buffer (like `MediaCentarr.Console.Buffer`).
* [ ] Audit usages of
  `acquisition_pursuits.last_queue_state` /
  `last_queue_health`. If only read for display: move to
  GenServer state in Pursuits.Reactor or similar.
* [ ] Schema migration if either moves out.

### D. Pattern documentation hygiene *(Pillar 2 + 3 docs)*

The Cache.Worker three-flavours pattern and the
*subscribe-canonical-emit-derived* PubSub convention are
currently scattered across several moduledocs. Consolidate so a
new contributor (or fresh agent context) finds the pattern in
one place.

* [ ] Centralise the three-flavour Cache.Worker pattern, either
  in a new section of ADR-041 or `lib/media_centarr/cache/README.md`.
* [ ] Centralise the PubSub topic taxonomy (canonical vs
  derived `*_view_updated`) — likely an addition to
  `lib/media_centarr/topics.ex` moduledoc.

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
