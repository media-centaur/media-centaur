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

Solver fix implemented 2026-06-10 (same session as diagnosis): the
per-unit-ensemble comparison is retired; consolidation claims spans
greedily in `{breadth, quality, seeders}` order and the hierarchy is
now **Coverage → Consolidation → User preference → Health**. The
Orville shape is pinned by a regression test (two 1080p packs + a 4K
single + high-seeder singles → exactly the two packs, no overlap).
REMAINING: live verification on prod after the next release. The
library-side audit stands: duplicates collapse to one Episode entity
(no UI double), but playback picks an arbitrary (insertion-order)
WatchedFile and both files persist on disk — deterministic file pick
stays a candidate follow-up.

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
* `2026-06-10` — Direction (user-aligned): pack wins consolidation at
  equal quality.
* `2026-06-10` — Open question resolved (autonomous, per "resolve what
  you can"): quality upgrades are **offer-as-swap only**, never
  auto-added — the user's stated expectation was "only the 2 season
  packs", and an auto-added upgrade is deliberate duplicate content.
  Within a span, consolidation now outranks per-unit quality; the
  plan board's alternatives picker keeps upgrades one click away.
  Supersedes the original summed-quality ensemble rule in the
  `Planner` moduledoc.

## Next steps

1. Verify against a live re-plan of a multi-season show on prod after
   the next release.

## Completion criteria

* No solved plan contains a release whose covered units are all also
  covered by another assigned release (no duplicate content grabs).
* Equal-quality, higher-seeder singles do not displace units from an
  assigned pack.
* A strictly-higher-quality single is reachable per unit via the plan
  board's alternatives picker (offer-as-swap) — never auto-assigned.
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
