---
status: accepted
date: 2026-08-31
---
# Plan diagnosis model: per-unit outcomes, per-title quality bounds, status-observed cancellation

## Context and Problem Statement

Three surfaces re-derived "what the search found" from different data:
the descent narrative (rung arithmetic), the gap verdict/evidence
(aggregate, movie-centric), and below-preference counting (movie path
only). TV plans therefore reported below-preference episodes as
unfindable. Separately, the quality bound resolved per-unit patience →
global default with no durable per-title layer, so a show whose world
is SD-only (e.g. a pre-HD sitcom) stays stranded behind a global 1080p
default forever, and any acceptance of that reality had nowhere to
live. Finally, discarding a plan mid-run only flipped its status; the
run searched to completion regardless.

## Decision Outcome

Chosen option: "one diagnosis model", because the board copy, the
acceptance policy, and cancellation are all views of the same fact set
and must not fork.

1. **Per-unit outcome is the one representation.** Each wanted unit's
   solve produces a closed-vocabulary outcome — kept /
   below_preference (with count and best release) / nothing — computed
   identically for movies and TV, persisted on the plan unit. Verdict,
   grid, and outcome rows are folds of it; no surface re-derives the
   facts. (Exact vocabulary and struct shape are moduledoc contracts.)
2. **Quality bounds resolve unit override → per-title preference →
   global default.** "Take SD for this show" writes the per-title
   layer — the same durable per-title home as the existing patience
   override — visible and resettable in Manage, snapshotted by plans at
   run time. ADR-061's invariant is intact and amended: gates still
   express bounds; bounds are per-title-resolvable. The dormant
   `plan.criteria["min_quality"]` slot must become that snapshot or be
   removed — it does not remain a third writable place.
3. **Plan status is the cancellation channel.** The run observes status
   at search-term boundaries and stops within one term; the existing
   discard transition machinery already treats mid-run exit as normal.
   No parallel cancel flag.

### Consequences

* Good, because TV gains below-preference parity as a by-product of
  unification rather than a copied banner path.
* Good, because acceptance persists correctly for free — later seasons
  and re-plans resolve the same per-title preference with no re-asking
  mechanism.
* Good, because stop-searching costs no new state and ends indexer
  traffic promptly.
* Bad, because the solve loop, unit persistence, and all board view
  models change together — campaign-sized, not a patch.
* Neutral, because auto-upgrade after acceptance (grab HD if it appears
  later) is explicitly out of scope; accepting SD promises nothing
  about upgrades.
