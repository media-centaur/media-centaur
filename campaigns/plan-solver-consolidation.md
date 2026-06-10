---
status: planning
started: 2026-06-10
last_updated: 2026-06-10
---
# Plan solver: packs must win at equal quality

## Goal

Stop the media-search planner from grabbing overlapping releases. A
real S2+S3 plan (The Orville, 2026-06-10, on v0.88.x) produced 7 grabs
/ ~59.5 GB where 2 season packs sufficed: the S3 pack lost to a
"fantasy ensemble" because one 4K single inflated the summed-quality
comparison, then the pack got grabbed *anyway* for the leftover
episodes — alongside ~11.6 GB of singles whose content is already
inside that pack. End state: a plan never assigns a release whose
units are fully duplicated by another assigned release, and equal-
quality singles never fragment a pack.

## Status

Diagnosed against the live plan board and the solver source; no code
yet. Root cause confirmed in `MediaCentaur.Acquisition.Planner` —
two compounding flaws (see Decisions). Library-side duplicate handling
also audited: duplicates collapse to one Episode entity (no UI
double), but playback picks an arbitrary (insertion-order) WatchedFile
and both files persist on disk.

## Decisions made

* `2026-06-10` — Diagnosis settled. Flaw A: `beats_ensemble?/4`
  compares the pack against the best *imaginable* per-unit lineup
  (summed quality, other packs allowed as providers, the lone 4K E01
  veto), but the loser-pack still re-enters `assign_singles/2` as a
  per-unit provider — so the user gets pack + duplicating singles, the
  worst of both. Flaw B: `assign_singles/2` picks per unit by
  `{quality, seeders}` with no consolidation preference — equal-quality
  singles with more seeders fragment a span, violating the module's own
  documented hierarchy (Coverage → Preference → Consolidation →
  Health).
* `2026-06-10` — Direction (user-aligned, not yet final design): pack
  wins consolidation at equal quality; strictly-better-quality singles
  may override *individual* units on top of an assigned pack (the 4K
  E01 case becomes pack + one upgrade, 2 grabs for the season). Open
  question: should a lone quality upgrade be auto-added or offered as
  a swap option only?

## Next steps

1. Design session: settle the upgrade-on-top-of-pack semantics
   (auto-add vs. offer-as-option) and whether the duplicate-content
   cost should be an explicit objective term.
2. Test-first in `planner_test.exs`: reproduce the Orville shape —
   1080p pack covering a full span + 4K single for one unit +
   higher-seeder 1080p singles for several units → assert pack-led
   solution, no overlapping assignments.
3. Implement in the pure solver (`Planner`); no I/O changes needed —
   the plan runner's search-all-rungs behavior is by design and stays.
4. Verify against a live re-plan of a multi-season show.

## Completion criteria

* No solved plan contains a release whose covered units are all also
  covered by another assigned release (no duplicate content grabs).
* Equal-quality, higher-seeder singles do not displace units from an
  assigned pack.
* A strictly-higher-quality single can still take its unit per the
  settled upgrade semantics.
* Regression test pinning the Orville shape (append-only per ADR-027).

## Pointers

* Solver: `lib/media_centaur/acquisition/planner.ex` —
  `beats_ensemble?/4` (span comparison), `assign_singles/2`
  (per-unit fallback). Pure module; high test leverage.
* Objective hierarchy doc: `Planner` moduledoc ("Coverage → User
  preference → Consolidation → Health").
* Library duplicate behavior (context for the follow-up, not this
  campaign's scope): `Library.populate_content_urls/1` takes the first
  WatchedFile with no ordering (`lib/media_centaur/library.ex`
  `populate_leaf_content_url/1`); a deterministic, quality-aware file
  pick when an episode has multiple files is a candidate follow-up.
