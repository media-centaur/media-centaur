---
status: in_progress
started: 2026-05-23
last_updated: 2026-05-23
---
# Presentable detail resolver (movie-vs-collection, one rule for all surfaces)

## Goal

A single rule decides whether an entity is presented as a movie or as a
collection, and *every* read surface (browse grid, detail modal,
now-playing/progress) consults that one rule. Fixes the reported bug
where a sole-possessed collection movie (e.g. only *Top Gun: Maverick*
owned from the Top Gun Collection) renders correctly as a movie in the
grid but as the **collection** in the detail modal. The grid and detail
must agree by construction, and the movie↔collection relationship must
survive as a reference (badge), never be lost.

## Status

Phase 1 (resolver) in progress. Design approved by user; explainer at
`~/.agent/diagrams/presentable-model.html` (not in repo).

## The model (approved)

- **Layer 1 — domain (unchanged):** `Movie.movie_series_id` → `MovieSeries`;
  possession = ≥1 present `WatchedFile` via `PlayableItem(:movie, …)`.
- **Layer 2 — the resolver:** `Library.resolve_presentable(id) :: {kind, id}`.
  The ONLY place the movie-vs-collection judgment lives.
  - standalone movie → `{:movie, id}`
  - collection, 1 present → `{:movie, sole_child_id}` (+ collection ref)
  - collection, ≥2 present → `{:movie_series, id}`
  - movie in a ≥2-present collection → `{:movie_series, ms_id}` (matches grid)
  - tv_series (present) → `{:tv_series, id}`; video_object → `{:video_object, id}`
  - else → `:not_found`
- **Layer 3 — per-surface views:** each surface resolves first, then builds
  the view for the resolved kind. Movie view carries the movie's OWN
  metadata + a collection **reference**.

## Realization

Reuse the single-item-per-PlayableItem Detail projection storage. Add a
`presented_as` field to `DetailItem` = the materialized hoist decision,
computed at build time from the collection's present-movie count. Make
`top_level_container(:movie, movie)` hoist-aware (the leverage point: all
`container_*` fields funnel through it, so they become movie-faithful for
sole-possessed automatically). `to_entity_map` dispatches on
`presented_as` (falls back to struct inference when nil, for back-compat
with existing fixtures); the movie view emits `collection: {id, name}`
from `parent_container_*`.

## Phases

1. **Resolver (additive).** `Library.resolve_presentable/1` + a
   present-movie-count helper. Unit + DataCase tests. No surface wired →
   no behavior change.
2. **Projection movie-faithful.** `presented_as` on `DetailItem`;
   hoist-aware `top_level_container`/`entity_grouping_key`; `to_entity_map`
   dispatch on `presented_as` + collection ref; canonical-index keys
   `{:movie_series, …}` only for `presented_as: :movie_series`.
3. **Wire surfaces.** `load_modal_entry/1` and
   `progress_broadcaster.load_via_detail/2` resolve via the resolver and
   build the resolved kind. Integration test reproducing the user bug.
4. **ADR + ship.** ADR for "presentable resolver as single authority";
   precommit; ship.

## Decisions made

* `2026-05-23` — Reuse single-item-per-PI storage with a `presented_as`
  field rather than a separate collection read model (lower blast radius;
  collection view keeps deriving from the representative child).
* `2026-05-23` — `to_entity_map` keeps struct-inference fallback when
  `presented_as` is nil so existing `detail_item_test` fixtures pass
  unchanged (ADR-027).

## Next steps

1. Phase 1 — resolver + count helper, test-first.
2. Phase 2 — projection `presented_as`.
3. Phase 3 — wire load_modal_entry + progress; integration test.
4. Phase 4 — ADR + ship.

## Completion criteria

* `Library.resolve_presentable/1` is the single hoist authority, tested.
* Opening a sole-possessed collection movie shows a faithful **movie**
  detail (its own title/facets) with a "Part of <collection>" reference.
* Multi-possessed collections still open as the collection.
* Grid and detail agree for every case; `mix precommit` green.

## Pointers

* `lib/media_centaur/library/presentable_queries.ex` — existing grid hoist rule (SQL).
* `lib/media_centaur/library/views/detail.ex` — projection builder + canonical index.
* `lib/media_centaur/library/views/detail_item.ex` — `to_entity_map`.
* `lib/media_centaur/library.ex` — `load_modal_entry/1`, `build_modal_entry/3`.
* `lib/media_centaur/playback/progress_broadcaster.ex` — `load_via_detail/2`.
