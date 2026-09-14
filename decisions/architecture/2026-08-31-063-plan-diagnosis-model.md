---
status: accepted
date: 2026-08-31
amended: 2026-09-07
---
# Plan diagnosis model: per-unit outcomes, per-title quality bounds, status-observed cancellation

## Context and Problem Statement

Three surfaces re-derived "what the search found" from different data, so
TV plans reported below-preference episodes as unfindable. Quality bounds
had no durable per-title layer, so a show whose world is SD-only stayed
stranded behind the 1080p default with nowhere to record acceptance.
Discarding a plan mid-run only flipped its status; the run searched on.

## Decision Outcome

One diagnosis model: the board copy, the acceptance policy and cancellation
are views of the same fact set and must not fork.

1. **Per-unit outcome is the one representation.** Each wanted unit's solve
   yields a closed-vocabulary outcome — kept, below preference (with count
   and best release), or nothing — computed identically for movies and TV
   and persisted on the plan unit. Verdict, grid and outcome rows are folds
   of it. The vocabulary and struct shape are moduledoc contracts.
2. **Quality bounds resolve unit override → per-title acceptance → global
   default.** The per-title layer is `Acquisition.TitleDownloadParams`,
   keyed by TMDB identity (moved there 2026-09-07 by
   [ADR-066](2026-09-07-066-one-ladder-per-title.md) §6; it was first a
   column on the tracked title, which forced "accept lower quality" to start
   tracking a show). Acceptance stores `min_quality: "any"`, a bound
   admitting unranked releases; manual plans snapshot a title's bounds into
   `plan.criteria` at creation. The gates of
   [ADR-061](2026-08-16-061-source-quality-ladder.md) still express bounds;
   bounds are per-title-resolvable.
3. **Plan status is the cancellation channel.** The run observes status at
   search-term boundaries and stops within one term; the existing discard
   transition treats mid-run exit as normal. No parallel cancel flag.

### Consequences

* Accepting lower quality promises nothing about upgrades; grabbing HD later
  if it appears is out of scope.
* The solve loop, unit persistence and every board view model change
  together.
