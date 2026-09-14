---
status: accepted
date: 2026-06-17
amended: 2026-06-17
---
# Canonical episode identity — one TMDB-anchored vocabulary, ambiguity only at the edges

## Context and Problem Statement

A tracked split-cour anime series sat with ten aired-but-missing episodes
that auto-grab kept "succeeding" on. TMDB models the show as one continuous
season; release groups name the second cour as a new season or by absolute
number. Wanting the later episodes, auto-grab searched the season, found a
"complete" pack of the first cour, grabbed it, and credited coverage from the
release's title — delivering nothing, reopening the wants, and re-grabbing
the same pack every tick.

## Decision Outcome

One rule survived this record (amended 2026-06-17, scope reduced):

1. **Coverage is proven by contents.** `Acquisition.Pursuits.LibraryReconciler`
   satisfies an episode unit only when that unit's own episode is present in
   the library, never by matching a release folder or title. A release that
   delivers nothing new is recorded as tried, so the planner never re-grabs
   it.

The rest of the original design — an `EpisodeIdentity` value with a derived
absolute ordinal and three edge adapters to auto-acquire TMDB-merged
split-cour shows — was dropped as over-scoped and its partial code removed.
TMDB stays the only metadata source, and the project carries no external
scene-numbering map (the XEM-style mapping Sonarr relies on). Such a show
sits honestly pending and is grabbed manually.

### Consequences

* The wrong-pack re-grab loop is structurally impossible.
* Broadcast-season-named releases for TMDB-merged shows are not found
  automatically.
