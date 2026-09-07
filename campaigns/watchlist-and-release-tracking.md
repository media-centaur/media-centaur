---
status: in-progress
started: 2026-09-07
last_updated: 2026-09-07
---
# Watchlist and release tracking

## Goal

Collapse four representations of one idea — a watchlist entry, a tracked title,
`Item.status`, `Item.auto_grab_mode` — into one authored intent and one derived
machine, and the three title modals that render them into two. A person should
declare "I want to watch this" once, arm it once, and see the same control
wherever the title appears.

## Status

**Phases 0 and 1 complete, unpushed.** The model is cut over: one
`tracking_mode` replaces `status` + `auto_grab_mode`, `source` is gone,
existence is reconciled from reasons, and `ReleaseTracking.arm/2` is the
person's act. `mix precommit` green (6854 Elixir + 807 JS). No visible change
yet — the UI still wears its old controls, wired to the new field.

**Migrated on this machine 2026-09-07**, against the real library DB
(`~/.local/share/media-centaur/media-centaur.db`, which the `media-centaur-dev`
daily driver uses): Fae backup first (`media-center-db`, success), service
stopped, `ecto.migrate` + `ecto.migrate_data`, service restarted and serving
(`/incoming` and `/discovery/watchlist` both 200, logs clean). Result: 13
tracked titles (12 `global`, 1 `watch`), 9 watchlist rows, and **0 active
tracked titles with no reason** — the invariant holds on real data. The old
columns are gone from the table.

**Phases 2–3 complete, unpushed** (`206eca0f`, `71a52275`): one title surface
for everything without files, and the library detail mounting the same two
components with the bell gone. The `:watching` / `:ignored` vocabulary is out of
the app entirely. Phase 4 (retire the stragglers line) is in progress with Fable.

## Decisions made

* `2026-09-07` — A watchlist entry is authored intent; a tracked title is
  derived machinery. A tracked title exists while a **tracking reason** holds:
  the library owns an active container, or a person armed the watchlist entry.
  `Item.source` is removed — it is write-once first-cause metadata, wrong for
  any title with both causes.
* `2026-09-07` — One **tracking mode** (None / Watch / Ask / Grab / Global)
  replaces `Item.status` and `Item.auto_grab_mode`. Set only by a person or
  seeded once at creation; **never raised by the system**. `Global` follows the
  ambient setting only while the mode has never been set explicitly.
* `2026-09-07` — Auto-grab is opt-in. A watchlist entry seeds **Watch**, not the
  global default: adding something to your list must never start a download.
  Library auto-track seeds **Global**, preserving today's behaviour.
* `2026-09-07` — Adding to the watchlist is free (no tracked title). Arming is a
  second act.
* `2026-09-07` — **The two reasons are not equivalent.** The library reason is a
  *default* and evaporates when the library stops owning the title; the
  watchlist reason is an *act* and outlives it. **Arming is a watchlist act** —
  choosing to track a title puts it on the watchlist, whatever surface the
  control was operated from. So: delete a series from the library and tracking
  continues iff a person had armed it; it stops if the global default was the
  only thing tracking it. Today's `detach_library_containers/1` keeps *every*
  item and so grabs forever regardless — a behaviour fix, not just a refactor.
* `2026-09-07` — **An explicit disarm is durable.** A row at mode None survives
  with no reason held — inert, invisible, no refresh, no wants — so re-acquiring
  or re-listing a title can never silently re-arm what a person turned off.
* `2026-09-07` — Invariant: **every *active* tracked title (mode above None) is
  either owned or on the watchlist.** Inert None rows exempt. This is what lets
  the straggler concept retire.
* `2026-09-07` — Three title modals become two, split by "does this have files"
  rather than by which table it came from. The release timeline and the
  tracking-mode control become shared components mounted by both.
* `2026-09-07` — `MediaCentaur.Discovery` / `MediaCentaur.Pipeline.Discovery`
  is **not** a collision — two contexts may use one word for different things.
* `2026-09-07` — UI phases are implemented with the Fable model; context,
  schema and migration phases stay on Opus.
* `2026-09-07` — Phase 0 landed: ADR-065, UIDR-035, five glossary terms.
* `2026-09-07` — Phase 1 landed and was migrated on this machine; the invariant
  verified on real data (0 orphans). Inert `:none` rows are never pruned —
  pruning one would re-arm the title.
* `2026-09-07` — Phase 2 landed. **Watchlist rows show the tracking mode as a
  quiet marker and never set it.** UIDR-035 says a row shows its mode; a
  five-option control repeated down a list reads as a chip palette and breaks
  `title_row.ex`'s own contract ("state is shown, never acted on here: every
  verb lives in the modal"). Arming stays one click away on the row's modal, so
  the watchlist is still the arming surface. Reverted after seeing it rendered.
* `2026-09-07` — `arm/2` takes an explicit `tracking_mode`, and re-arming a
  disarmed title raises it to the seed. Not the system raising a mode: every
  caller is a person's click. `disarm/1` / `arm/2` write their
  `:stopped_tracking` / `:began_tracking` audit events so the modal's recent
  activity still records a stop.
* `2026-09-07` — `TitleDetailHost` is the shared host trait for the merged
  modal, and `TitleRef` owns the `?title=` ref spelling now that both Discovery
  and Incoming use it.
* `2026-09-07` — Phase 3 landed: the library detail mounts the same timeline and
  mode control, the bell is gone, and `tracking_status` became `tracking_mode`
  through the view models.
* `2026-09-07` — **Suite flakes here are contention, not regressions.** Two
  agents running the full suite at once race for the test database and produce a
  rotating cast of ~4–5 failures; the committed baseline shows the same rate.
  Verify a change against its own test surface repeated, and run one full
  precommit at a time.

## Next steps

1. ~~**Phase 0 — records and vocabulary.**~~ Done 2026-09-07:
   [ADR-065](../decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md),
   [UIDR-035](../decisions/user-interface/2026-09-07-035-two-title-surfaces.md),
   and five glossary terms (*watchlist entry*, *tracked title*, *tracking
   reason*, *tracking mode*, *arming* — none existed, which was the diagnosis in
   miniature). *Straggler* marked retired-pending-Phase-4.
2. ~~**Phase 1 — the model.**~~ Done 2026-09-07. `tracking_mode` replaces `status` +
   `auto_grab_mode`; `source` dropped; existence reconciled from reasons;
   `ReleaseTracking.WatchlistListener` mirroring `LibraryListener`;
   `TrackingStarted` broadcast moves to Discovery. `detach_library_containers/1`
   becomes a reconcile rather than a detach. Four paired migrations per the
   spec, including backfilling watchlist entries for `source: :manual` items —
   without it the invariant fails on first reconcile and manually tracked titles
   are stranded. Existing controls keep working: the bell writes `tracking_mode`
   via `EntityModal.toggled_tracking_mode/1`. No visible change.

   Landed beyond the plan: `Item.grab_mode/2` is now the single resolver of
   mode → grab decision (it had been copied three ways, in `AutoGrabSettings`,
   `Present` and `UpcomingFeed`, each reaching into `item.auto_grab_mode`
   directly — the actual boundary violation under the duplication);
   `list_watching_items/0` → `list_active_items/0`; a
   `DropOrphanedTrackedTitles` data migration sweeps rows the old
   keep-everything `detach` left behind. Inert `:none` rows are deliberately
   never pruned — pruning one re-arms the title.
3. ~~**Phase 2 — merge the no-files surfaces**~~ Done 2026-09-07 (`206eca0f`). `ReleaseTracking.TitleModal`
   absorbed into `Discovery.TitleDetailModal`; shared release-timeline and
   tracking-mode components extracted; watchlist rows gain the mode control;
   the `Track` verb retired in favour of add + arm. Ships a working product;
   the bell remains a knowingly-stale second representation until Phase 3 — an
   explicit scheduled convergence, not a silent one.
4. ~~**Phase 3 — library detail**~~ Done 2026-09-07 (`71a52275`). Mounts the same two shared components;
   the bell is removed. The convergence point for Phase 2's debt.
5. **Phase 4 — retire the stragglers line** (Fable). `UpcomingFeed.Straggler`
   removed, Coming up reduced to the schedule, UIDR-017 amended.
6. **Phase 5 — docs.** `priv/guide/release-tracking-and-upcoming.md` rewritten
   around the new vocabulary (it currently teaches Track-vs-watchlist), a guide
   page for the watchlist (there is none today), wiki sync, glossary elevation.

## Completion criteria

* `release_tracking_items` has one `tracking_mode` and no `status` or `source`.
* A tracked title's existence is reconciled from reasons; nothing writes it directly.
* The invariant holds on real data: no *active* tracked title that is neither owned nor listed.
* Deleting a series from the library stops tracking it unless a person armed it; an explicit disarm survives every list change.
* Two title surfaces, both mounting the same release-timeline and tracking-mode components.
* No bell, no `Track` verb, no straggler line.
* Guide and wiki describe one intent and one machine; glossary carries all four terms.
* `mix precommit` green; migrations idempotent and CHANGELOG-mentioned.

## Pointers

* Design: `docs/superpowers/specs/2026-09-07-watchlist-release-tracking-reconciliation-design.md`
* Prior watchlist design: `docs/superpowers/specs/2026-08-18-watchlist-foundation-design.md`
* [ADR-056](../decisions/architecture/2026-06-10-056-release-tracking-wants.md) — wants
* [UIDR-017](../decisions/user-interface/2026-08-03-017-coming-up-title-depth.md) — Coming Up title depth; straggler half superseded here
* Key modules: `lib/media_centaur/discovery.ex`, `lib/media_centaur/release_tracking.ex`,
  `lib/media_centaur/release_tracking/{item,auto_track,library_listener,wants}.ex`,
  `lib/media_centaur_web/components/{discovery/title_detail_modal,release_tracking/title_modal}.ex`,
  `lib/media_centaur_web/live/entity_modal.ex`
