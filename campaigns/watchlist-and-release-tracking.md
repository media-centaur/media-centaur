---
status: planning
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

Planning. Design agreed 2026-09-07 and written to
`docs/superpowers/specs/2026-09-07-watchlist-release-tracking-reconciliation-design.md`.
No code yet.

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
  second act. Removing an entry sets mode to None and deletes the tracked title
  unless the library reason holds, in which case the disarm survives on the row.
* `2026-09-07` — Invariant: **every tracked title is either owned or on the
  watchlist.** This is what lets the straggler concept retire.
* `2026-09-07` — Three title modals become two, split by "does this have files"
  rather than by which table it came from. The release timeline and the
  tracking-mode control become shared components mounted by both.
* `2026-09-07` — `MediaCentaur.Discovery` / `MediaCentaur.Pipeline.Discovery`
  name collision noted and **deferred** — adjacent, not caused by this work.
* `2026-09-07` — UI phases are implemented with the Fable model; context,
  schema and migration phases stay on Opus.

## Next steps

1. **Phase 0 — records and vocabulary.** ADR-065 (tracking reasons, the derived
   tracked title, the invariant, removal of `source`). UIDR-035 (two title
   surfaces; retirement of the straggler line, superseding that half of
   UIDR-017). Glossary entries for *watchlist entry*, *tracked title*,
   *tracking reason*, *tracking mode* — none exists today, which is the
   diagnosis in miniature.
2. **Phase 1 — the model.** `tracking_mode` replaces `status` +
   `auto_grab_mode`; `source` dropped; existence reconciled from reasons;
   `ReleaseTracking.WatchlistListener` mirroring `LibraryListener`;
   `TrackingStarted` broadcast moves to Discovery. Four paired migrations per
   the spec, including backfilling watchlist entries for `source: :manual`
   items — without it the invariant fails on first reconcile and manually
   tracked titles are stranded. Existing controls keep working: the bell writes
   `tracking_mode`. No visible change.
3. **Phase 2 — merge the no-files surfaces** (Fable). `ReleaseTracking.TitleModal`
   absorbed into `Discovery.TitleDetailModal`; shared release-timeline and
   tracking-mode components extracted; watchlist rows gain the mode control;
   the `Track` verb retired in favour of add + arm. Ships a working product;
   the bell remains a knowingly-stale second representation until Phase 3 — an
   explicit scheduled convergence, not a silent one.
4. **Phase 3 — library detail** (Fable). Mounts the same two shared components;
   the bell is removed. The convergence point for Phase 2's debt.
5. **Phase 4 — retire the stragglers line** (Fable). `UpcomingFeed.Straggler`
   removed, Coming up reduced to the schedule, UIDR-017 amended.
6. **Phase 5 — docs.** `priv/guide/release-tracking-and-upcoming.md` rewritten
   around the new vocabulary (it currently teaches Track-vs-watchlist), a guide
   page for the watchlist (there is none today), wiki sync, glossary elevation.

## Completion criteria

* `release_tracking_items` has one `tracking_mode` and no `status` or `source`.
* A tracked title's existence is reconciled from reasons; nothing writes it directly.
* The invariant holds on real data: no tracked title that is neither owned nor listed.
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
