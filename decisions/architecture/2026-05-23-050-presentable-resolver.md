---
status: accepted
date: 2026-05-23
---
# A single presentable resolver decides movie-vs-collection for every surface

## Context and Problem Statement

Whether a movie in a TMDB collection shows as the movie or as the collection is a possession decision: one owned member hoists the movie, two or more show the collection. The rule lived only in the browse grid query and the detail projection re-inferred type from struct shape, so one entity rendered as a movie in the grid and as its collection in the modal.

## Decision Outcome

1. **One rule, two ways to consume it.** The possession count is expressed once, in `Library.Presentable`. A surface either calls `Library.Presentable.resolve/1` (id → `{kind, id}`) or reads the outcome the detail projection materialised from the same rule (`DetailItem.presented_as`). No surface re-implements or re-infers it.
2. **Read models carry facts and a materialised decision.** `DetailItem.to_entity_view/1` dispatches on `presented_as`; a hoisted movie is built movie-faithfully with the collection kept as a reference.
3. **Relationships are never collapsed.** `Movie.movie_series_id` is untouched and the collection stays queryable.

[UIDR-025](../user-interface/2026-08-14-025-collections-are-filing-not-content.md) narrows the scope to filing surfaces and click routing: activity surfaces always present movies.

### Consequences

* The detail projection runs a possession count per collection movie at build time.
