---
status: accepted
date: 2026-05-23
---
# A single presentable resolver decides movie-vs-collection for every surface

## Context and Problem Statement

A movie can belong to a TMDB collection (`MovieSeries`). Whether the
library should show that movie *as a movie* or *as a collection* is a
**presentation decision** that depends on possession: a collection with
one owned movie should surface the movie directly; with two or more it
should surface the collection container. This "hoist" rule is correct
and intended.

The bug: the rule lived in only one place — the browse grid query
(`PresentableQueries`). Other read surfaces re-derived presentation type
independently. The detail projection (`Views.Detail` →
`DetailItem.to_entity_map/1`) inferred type from the stored struct shape
("this movie has a `movie_series` parent → render the collection"),
baking the *policy* into the read-model's stored *data*. So a
sole-possessed collection movie rendered correctly as a movie in the
grid but as the **collection** in the detail modal — two surfaces, two
answers, for the same entity.

## Decision

1. **One rule for the hoist decision, two ways to consume it.** The
   movie-vs-collection judgment is the possession count (1 → movie, 2+ →
   collection), expressed once and shared. A surface obtains the decision
   either by **calling** `Library.resolve_presentable/1` (id → `{kind, id}`,
   e.g. the detail modal, which then builds the view for the resolved
   kind) or by **reading the materialized outcome** the projection
   stamped from the same rule (`DetailItem.presented_as`, consumed by the
   projection-backed surfaces). No surface re-implements or re-infers the
   policy.

2. **Read models carry facts and a materialized decision, never re-infer
   policy.** The detail projection stamps the hoist outcome onto each row
   as `DetailItem.presented_as`, computed once at build time from the same
   possession count the grid uses. `to_entity_map/1` dispatches on
   `presented_as` rather than guessing from the struct shape. A
   sole-possessed collection movie is built movie-faithfully (its own
   metadata) with the collection kept as a **reference** (`:collection`),
   not by morphing the whole view into the collection.

3. **Relationships are never collapsed.** The domain (`Movie.movie_series_id`)
   is untouched; the connection is always queryable and surfaced as a
   badge reference even when a movie is hoisted out of its collection.

## Consequences

- The grid, detail modal, and playback progress can no longer disagree
  about whether something is a movie or a collection — they share one
  rule and one materialized decision.
- The decision is computed from possession, so it updates itself: owning
  a second movie in a collection flips presentation everywhere at once.
- New read surfaces resolve through `resolve_presentable/1` instead of
  re-implementing the rule — cheap and safe to add.
- A read model must not encode "how to present" into "what is stored".
  When a surface needs a presentation decision, it asks the resolver; the
  stored shape carries facts plus the materialized outcome, nothing more.
- Cost: the projection build runs a possession count per collection-movie
  (cheap, indexed; on the non-hot refresh path). Acceptable for the
  correctness and consistency it buys.

Supersedes the implicit assumption in the Library Schema v2 Phase 3.2
detail projection that a movie-in-a-collection always renders as the
collection.
