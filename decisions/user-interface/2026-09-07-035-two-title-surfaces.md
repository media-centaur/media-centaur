---
status: accepted
date: 2026-09-07
amended: 2026-09-14
---
# Two title surfaces, split by whether the title has files

Supersedes UIDR-017 (retired). UIDR-036 superseded its `Remove from watchlist` clause.

> **Amendment 2026-09-14 (later) — superseded in part by UIDR-043.** Rules 1 and 2 (two surfaces split by whether the title has files) and the page-membership clause of the amendment below no longer hold: one title detail modal, composed by facts, opens on every page for every TMDB identity; files are one fact among the others. Rules 3–6 stand.

> **Amendment 2026-09-14 — the title detail's subject is a TMDB identity,
> not a page membership.** As shipped, the title detail modal on Discovery
> and Incoming was held open only while the hosting page still listed the
> title, and its URL (`?title=<media_type>-<tmdb_id>`) opened only a title
> the receiving page already knew. Two consequences the owner named as
> hostile: un-bookmarking a title you had listed yourself removed it *and*
> closed the modal, taking the toggle's own undo with it (a title with
> friend activity stayed open); and "the URL is shareable" held only between
> installs with the same lists. Decided: the host (`Live.TitleDetailHost`)
> resolves the snapshot by identity — the open detail's own, the title
> intent's, the page's in-memory copy, then TMDB itself fetched
> asynchronously — so a deep link opens any TMDB title, on any install with
> a TMDB key, and an open detail is never closed by the lists changing
> beneath it. What stands in the way of a fetched open (no key, no such
> title, no answer) is flashed and the param dropped. Friend activity and
> the intent's note are read by identity too, so the pennant flies on the
> Incoming surface as UIDR-037 requires. A page supplies only what it alone
> holds (`page_facts/3`). Campaign `title-detail-deep-links` (completed and
> removed — see git history).

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
