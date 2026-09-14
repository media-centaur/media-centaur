---
status: accepted
date: 2026-08-11
amended: 2026-09-14
---
# Gap banner states the diagnosed world, with its evidence — never a bare "not available"

## Context and Problem Statement

When a plan finished with gaps, the banner asserted "N not available right now" without evidence, collapsing several worlds into one claim: results came back and were all rejected, no indexer returned anything, the emptiness was served stale from the corpus, or the search was blind. The user could not tell "the world has nothing" from "the app rejected what the world offered".

## Decision Outcome

1. **The banner states the diagnosed world**, derived mechanically from counts the plan run already computes, never an inferred cause. `GapVerdict`'s worlds, in precedence order: `:blind` (UIDR-016); `:below_preference` (UIDR-029); the calendar worlds `:unreleased` / `:in_theaters` (amended 2026-09-14: from `TMDB.ReleaseWindow`, a movie with no home release yet gets the dates as its headline with the search evidence carried through; movies only; a theatrical opening with no home date counts as in theaters for 180 days; fetched per board open, never stored on the plan); `:no_evidence`; `:rejected` ("14 results came back, but none looked like this movie", with **Show them anyway** opening the alternatives panel over the rejected releases, the override for a matcher false negative); `:nothing_live`; `:nothing_stale` (stale corpus results; Search again is the remedy); `:searching`.
2. **Evidence persists with the pursuit** and is cleaned up when its story ends, so the banner renders identically on a modal reopened days later.
3. **Visual scope**: the existing glass-inset warning row, amber confined to the icon and verdict line, evidence as muted prose, no chips or tables. UIDR-029 later promoted the verdict to the board's headline.
4. **The empty board's footer carries the watchlist bookmark** (amended 2026-09-14, [UIDR-039](2026-09-11-039-add-to-watchlist-then-the-tracking-controls.md)) in the slot Approve would hold, so the remedy for "not out yet" is offered where the diagnosis is given.

### Consequences

* The plan run persists a small search report it used to discard.
* TV gaps get an aggregate sentence; per-unit world diagnosis is deferred.
