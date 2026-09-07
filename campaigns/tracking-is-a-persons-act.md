---
status: planned
started: 2026-09-07
last_updated: 2026-09-07
---
# Tracking is a person's act

## Goal

A person holds one standing intent per title, on a ladder; every tracked
title, calendar row, want and plan is machinery derived from where that
intent sits. The app never puts a title on the ladder itself, and the
bottom of the ladder deletes.

## Status

Planned 2026-09-07. Design:
[`docs/superpowers/specs/2026-09-07-tracking-is-a-persons-act-design.md`](../docs/superpowers/specs/2026-09-07-tracking-is-a-persons-act-design.md).
No code yet.

## Decisions made

* `2026-09-07` — **Tracking starts only by a person's act.** No code path
  creates a tracked title as a side effect of something else. The real
  inventory, in what a person does: library import (fully silent);
  "Download all" (a bolt-on the menu never mentions); "Accept lower
  quality" (creates a tracked title only to have somewhere to store
  `min_quality`); the gap banner's "Track these later" and the plan
  modal's "Also grab future episodes" (both already clicks, both
  under-describing themselves). `Scanner` is a sixth writer with no
  caller in `lib/`.
* `2026-09-07` — **Off deletes.** The bottom rung deletes the record and
  everything derived from it. The row kept as a "durable disarm" existed
  only to veto the automatic paths above; with those gone it has no job.
* `2026-09-07` — **The ladder converges into one authored record**
  (`/unify_design`). The person's intent was stored in two tables
  (watchlist presence, `Item.tracking_mode`) and rendered by two controls
  (Add to watchlist, the five-button strip). One record, one rung, one
  control, one write path. `Reasons`, `WatchlistListener`, `arm/2` and
  `disarm/1` are deleted rather than trimmed, and "a tracked title that
  is not on the list" becomes unrepresentable instead of enforced.
* `2026-09-07` — **The record is `Discovery.TitleIntent`**, table
  `title_intents`. "Watchlist item" named one surface; the record now
  carries the whole ladder.
* `2026-09-07` — **Rungs are `Off · List · Follow · Ask · Grab ·
  Default`.** *plan* and *track* were rejected as rung names: *plan* is
  `Acquisition.Plans.Plan`, the draft the Ask rung parks, and *track* is
  the machinery — every rung above Follow tracks too.
* `2026-09-07` — **Library import replaces automatic tracking with
  nothing.** No prompt, no suggestion list. Coming up shows only what a
  person put there.
* `2026-09-07` — **On upgrade, every tracked title with no watchlist
  entry stops.** 6 of 13 on this install.
* `2026-09-07` — **The Download menu gets a third entry.** *Download
  first season*, *Download all*, *Download all and track*. Only the third
  puts the title on the ladder.

## Answered while planning

* The gap handoff is **already** behind a click ("Track these later"). It
  neither stops nor asks anew — it says what it does and sets a rung.
* Titles already auto-tracked: **removed** unless a person had listed
  them.

## Found while planning

Two live bugs, both the same class this campaign is about — the act and
the outcome do not match. `Item.grab_mode(:watch, _)` returns `"off"` and
`DropPlanner.plan_item/4` bails on `"off"`, so a title at Watch never
searches and never grabs. Therefore:

* **"Also grab future episodes" never grabs.** It seeds `:watch`. If the
  title was already tracked it changes nothing at all.
* **"Track these later" cannot keep looking.** Same seed; the gap wants
  are written and then skipped, while the flash promises a search.

And one live contradiction of ADR-065: `LibraryLinks.refresh_for/1:88`
deletes a tracked title outright when its library container is gone,
bypassing `Reasons` — so a title a person armed *and* owns is destroyed
by deleting the library folder.

## Next steps

1. Write the implementation plan from the design doc.
2. Phase 1 — download params leave release tracking.

## Completion criteria

* No code path creates a tracked title without a person asking for it.
* Off deletes the record and its machinery.
* One authored record, one rung, one control, one write path.
* ADR-065 and UIDR-035 superseded where they conflict; glossary elevated
  to `docs/GLOSSARY.md`.
