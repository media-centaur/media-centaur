---
status: in-progress
started: 2026-08-08
last_updated: 2026-08-08
---
# Collection detail coherence — apply the TV modal lessons to movie / movie-series

## Goal

The TV detail modal (v0.118.0) established the detail pipeline: resolve
container kind once → compose a typed view model (content ADT +
cross-context overlays + orientation) → render type-appropriate rows in
the shared shell. Movie / movie-series still bypass it: untyped
`ModalEntry` map, inline sorting/ordinals in the component, no
orientation, no release overlay, fat rows around data the projection
doesn't even carry. Bring collections onto the same pipeline so the
modal is coherent with how it would be designed greenfield.

## Settled design (2026-08-08, approved by owner)

* **One loader.** `Presentable.resolve/1` once, then dispatch:
  `:tv_series` → `SeriesDetail`, `:movie_series` → new
  `CollectionDetail`, leaves → the `ModalEntry` map (leaves have no
  content list to type — principled boundary, kept). Kills the
  probe-and-fallback chain in `EntityModal.load_entry/1` (wasted
  `:tv_series` projection query per non-TV open).
* **`CollectionDetail` + `MovieListItem` ADT** mirroring
  `SeriesDetail`: `Library` (movie, precomputed `state`,
  `is_resume_target` by target id) and `Upcoming` (release-tracking
  overlay — announced collection parts via
  `list_relevant_releases_for_library_container(id, :movie)`, matched
  by `part_tmdb_id`, deduped per part). **No `Missing` variant** — the
  Library doesn't store known-but-absent collection parts; named
  convergence point for a future collection-completeness feature.
  `with_progress/4` for in-memory tick merges, like TV.
* **Orientation generalized**: same struct, second constructor for
  collections (fraction = watched/total, autoscroll mid-collection, no
  season/expansion projections). `detail_panel` keys hairline /
  autoscroll / PlayCard-percent suppression off orientation *presence*,
  not `type == :tv_series`. Rule: containers with an ordered playable
  set get the hairline; leaves keep the PlayCard row.
* **Dense movie rows** in the episode-row idiom: title (+year) ·
  duration · disclosure chevron · watched toggle; poster + synopsis
  inside the disclosure. Requires member-movie projection to carry
  images/description/tmdb id (`DetailItem.movie_entry_to_map/1`).
  Upcoming rows reuse the muted calendar-pill idiom.
* **Componentization split** of `detail_panel.ex` (1360 lines):
  `detail/season_list.ex`, `detail/collection_list.ex`,
  `detail/extras.ex`, shared row chrome (watched toggle, progress
  underline ×3 today, state classes, disclosure) in one module.
  Stories per MC0009 in the same change.
* **Leaf-id addressing (final stage, approved):** rows send leaf UUIDs
  (`phx-value` container id) for toggle_watched; retire `{0, ordinal}`
  and `{season, episode}` from the UI event layer (touches TV path);
  unify disclosure key-space to leaf ids.
* Rolled-in fixes: movie_series in `releases_updated` PubSub refresh;
  drop duplicate "Movies" facet (dup of metadata row); correct stale
  `MovieList` moduledoc (ordinal-keyed WatchProgress claim);
  type-appropriate hairline aria-label.

## Stages

1. Typed spine: `MovieListItem`, `CollectionDetail` (+ overlay +
   `with_progress`), unified loader dispatch, PubSub refresh — tests
   first.
2. Orientation for collections + detail_panel guard removal.
3. Projection enrichment + dense rows + upcoming rows + facet dup fix.
4. Componentization split + stories.
5. Leaf-id addressing convergence (TV included) + moduledoc fix.

## Status

Stage 1 in progress (2026-08-08).

## Relationship to other campaigns

* `playable-item-versions.md` — versions of one movie; orthogonal. The
  old `detail_panel` comment pointing the movie-series view-model at
  that campaign is superseded by this one.
* Wiki follow-up on completion: *Using Media Centaur* library page
  (collection modal shows announced parts of tracked collections).

## Next steps

* Stage 1 red tests: `CollectionDetail.build/4` unit tests + loader
  dispatch tests.
