---
status: accepted
date: 2026-09-07
amended: 2026-09-07
---
# Two title surfaces, split by whether the title has files

Supersedes UIDR-017 (retired). UIDR-036 superseded its `Remove from watchlist` clause.

## Context and Problem Statement

Three modals rendered one title, split by source table: library detail for owned titles, a Discovery modal for unowned ones, a release-tracking modal per tracked item. Nobody outside the code can perceive it; a title changed modal, route and vocabulary through its life, and an owned series with an announced season sat in two.

## Decision Outcome

1. **Library detail** (`DetailPanel`) is the surface for titles with files. It gains the release timeline and the tracking controls; the bell toggle is removed.
2. **Title detail** (`Components.Title.DetailModal`) is the surface for titles without files; it absorbs the release-tracking modal.
3. **The release timeline (`ReleaseTracking.ReleaseTimeline`) and the tracking controls (`Title.IntentControl`) are shared components mounted by both.** Content: UIDR-036, UIDR-039; model: ADR-066.
4. **`Track` and `Stop tracking` disappear as verbs**; listing a title and setting its rung replace them.
5. **Three lists, one job each:** the watchlist is authored intent and where the rung is set, rows showing rung and next date; Coming up is the schedule of dated releases; the library is what you have.
6. **The "Not scheduled yet" stragglers line is retired**, and `UpcomingFeed.Straggler` with it: an undated followed title is visible on the watchlist.

### Consequences

* Touches `DetailPanel`, the most load-bearing UI; sequenced last.
