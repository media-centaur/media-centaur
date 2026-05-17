# Library Schema v2 — Phase 3.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to execute task-by-task. Steps use checkbox (`- [ ]`). Invoke `automated-testing`, `ecto-thinking`, `phoenix-thinking`, and `coding-guidelines` BEFORE touching code.

**Goal:** Migrate the entity-detail modal (`/library?selected=<id>` and the cross-page modal opened from cards on `/` and `/upcoming`) from `Library.load_modal_entry/1`'s rich-Repo-preload path to a thin composition over `Library.Views.Detail` + `Library.Views.detail_by_container/2`. End state: opening the detail modal hits Pillar 2 (ETS) for Library data; only ReleaseTracking and Playback overlays touch the DB.

**Architecture premise (unchanged from Phase 3):** local desktop app, statefulness is an asset, projections are Pillar 2, LiveViews subscribe to derived topics. Phase 3.1 proved the BrowseItem-plus-bulk-helpers composition pattern for LibraryLive's grid; Phase 3.2 applies the same shape to the heaviest remaining DB-on-modal-open path.

**Campaign references:**
* [`campaigns/library-schema-v2.md`](../../../campaigns/library-schema-v2.md) — DetailLive flip is the Phase 3 Task E E.3 deferral.
* [`campaigns/desktop-rearchitecture.md`](../../../campaigns/desktop-rearchitecture.md) — Workstream A's "every read path through a projection" criterion. Open follow-up: "DetailLive / EntityModal consumer flip."

**Tech stack:** Phoenix 1.7+, Ecto 3.12+, SQLite via ecto_sqlite3, ETS, `MediaCentarr.Cache` behaviour (ADR-041).

**Scope honesty:** this plan is the *design* artifact. Implementation lands in subsequent sessions, one task per commit, dispatch-implement-review-fix loop. Treat the field set in Task A as the binding contract — every consumer flip later refers back to it.

---

## Test-design principles

Same load-bearing rules as Phase 3 — read [`2026-05-16-library-schema-v2-phase3.md`](2026-05-16-library-schema-v2-phase3.md#test-design-principles-load-bearing--read-before-any-task) for the full list. Highlights for Phase 3.2:

* **No DB in projection-driven render paths.** `no_db_on_render_test`'s budget for `/library?selected=<id>` and `/movie/<id>` etc. drops to the same ~5-query floor that Browse hit (Cache.Worker hot path: ETS lookup + bulk overlays for cross-context data).
* **Cross-context composition stays at the LiveView layer.** Library.Views.Detail must remain Library-pure. ReleaseTracking releases and Playback now-playing remain LiveView-layer overlays, exactly the pattern HomeLive uses for `coming_up` + grab-status enrichment.
* **`SeriesDetail.compose/1` and `Library.load_modal_entry/1` are coexisting paths today.** The cutover does not delete them in one swing — Task D measures the new read path against the old via parameterised test, then Task E retires the old.

---

## Current state — what the modal reads

### Modal entry points

| Route | Host LiveView | Modal opener |
|---|---|---|
| `/library?selected=<id>` | `LibraryLive` | poster card click in catalog grid |
| `/?selected=<id>` | `HomeLive` | Continue Watching / Recently Added / Hero card click |
| `/upcoming?selected=<id>` | `UpcomingLive` | upcoming-row click |

All three use `use MediaCentarrWeb.Live.EntityModal`; the modal is identical across pages.

### Two compose paths today

1. **TV series:** `MediaCentarrWeb.ViewModel.SeriesDetail.compose/1` →
   - calls `Library.load_modal_entry/1` (rich entity + preloads + extras backfill)
   - calls `ReleaseTracking.list_relevant_releases_for_library_container/2`
   - calls `ResumeTarget.compute/2`
   - builds typed `%SeriesDetail{}` with `[SeasonView]` + `[EpisodeListItem]`
2. **Movie / MovieSeries / VideoObject:** `Library.load_modal_entry/1` directly →
   - calls `Library.Browser.fetch_typed_entries_by_ids/1`
   - calls `Library.load_extras_for_entity/1` (1-2 extras queries)
   - returns rich-`entity` shape; modal consumes via untyped `:entity, :map` attrs

### Fields the rendering layer consumes

Inventoried 2026-05-17 across `detail_panel.ex`, `detail/hero.ex`, `detail/logic.ex`, `detail/more_info_panel.ex`, `detail/more_info/cast_grid.ex`, `more_info/series_credits.ex`, `more_info/movie_credits.ex`, `more_info/external_links.ex`, `more_info/people.ex`, `play_card.ex`, `subtitles_row.ex`, plus the typed `SeriesDetail` composer.

**Leaf-level (already in `DetailItem`):**
* `playable_item_id`, `container_type`, `container_id`, `name`, `position`, `duration_seconds`, `date_published`, `description`
* `parent_container_*` (for episode → series)
* `container_*` metadata bundle (description, year, url, tagline, genres, studio, country_code, original_language, network, status, duration_seconds, content_rating, aggregate_rating, vote_count, number_of_seasons)
* `cast`, `crew`, `extras`, `external_ids`, `imdb_id`, `tmdb_id`, `present?`

**Missing — required for the modal cutover:**

| Field | Used by | Why |
|---|---|---|
| `:images` | `Hero` (backdrop + logo), poster fallback | Currently entity-preloaded; modal hero needs backdrop URL + logo URL + poster URL |
| `:seasons` (TV) | `DetailPanel.season_section`, `SeriesDetail.build/4` | Typed `[%DetailItem.Season{}]` carrying static episode metadata; per-episode progress overlays at the consumer |
| `:movies` (MovieSeries) | `DetailPanel.content_list/1`, `MovieList.sort_movies/1` | Typed `[%DetailItem.MovieEntry{}]` with name, date_published, content_url, position; progress overlays at the consumer |
| `:watched_files` (leaf) | delete-file/folder UX, content_url resolution | Typed `[%DetailItem.WatchedFile{}]` — one row per backing file on disk |
| `:subtitle_tracks` (leaf) | `SubtitlesRow` | Typed `[%DetailItem.SubtitleTrack{}]` carrying kind + language + source. Decision: inline on projection refresh (default) or bulk-overlay at modal open — Task B settles based on cold-start build time |
| ~`:extra_progress`~ | n/a | **REMOVED 2026-05-17 (Task A decision).** Progress overlays at LiveView via `Library.Progress.get/1`, same pattern as BrowseItem in Phase 3.1. Avoids invalidating Detail projection on every playback tick |
| `:tracking_status` | `SeriesDetail` builder, modal toggle button | Read from `ReleaseTracking.lookup_tracking_status/1`; cross-context overlay, **stays at LiveView layer**, not on DetailItem |

### Cross-context overlays — stay at LiveView layer

| Overlay | Source | Pattern reference |
|---|---|---|
| Tracking status | `ReleaseTracking.lookup_tracking_status/1` | HomeLive's grab-status enrichment over `coming_up` |
| Future-season releases | `ReleaseTracking.list_relevant_releases_for_library_container/2` | Same |
| Now-playing | `Playback.MpvSession` | LibraryLive's existing playback assigns |

The projection emits Library data; the LiveView composes the cross-context layers on read. This was the pattern that kept the HomeLive flip inside the ReleaseTracking boundary in Phase 3 (decision `2026-05-10` in the campaign).

---

## Tasks

### Task A — Expand `DetailItem` shape *(Pillar 2 contract)*

**Goal:** Define every field the modal needs, fail compilation everywhere a consumer reads a missing key. No DB code yet; DetailItem is a struct-with-types change.

- [x] Add `:images, :seasons, :movies, :watched_files, :subtitle_tracks` to the struct and `@type t`. (`:extra_progress` dropped per the design decision above — progress is overlay, not embedded.)
- [x] Inner structs declared in the same file: `DetailItem.Season`, `DetailItem.Episode`, `DetailItem.MovieEntry`, `DetailItem.WatchedFile`, `DetailItem.SubtitleTrack`. Plain `defstruct + @enforce_keys + @type t` following the `EpisodeListItem` precedent.
- [ ] Update `DetailItem` storybook fixtures to populate the new fields with realistic data so the existing detail stories keep rendering. **(Deferred — no existing DetailItem-typed storybook attr exists yet; storybook flip lands at Task E alongside the consumer migration.)**

**Tests:**
* [x] `test/media_centarr/library/views/detail_item_test.exs` — struct-shape unit test (`async: true`, 12 cases). Covers field defaults + required-key enforcement for DetailItem and each inner struct.

**Acceptance:** `DetailItem` struct compiles; existing projection-builder + consumer files keep compiling because the new fields default to nil. **Shipped 2026-05-17.**

---

### Task B — Expand `Library.Views.Detail.refresh_cache/0` *(Pillar 1 → Pillar 2)*

**Goal:** Populate the new DetailItem fields from Pillar 1 in the projection's cold-start + incremental-refresh paths.

- [ ] Read every `PlayableItem` + container preloads needed to populate the expanded shape. For TV: `seasons → episodes → playable_items + watched_files + watch_progress`. For MovieSeries: `movies → playable_items + watched_files + watch_progress`. For Movie/VideoObject: single-leaf preload with `watched_files`.
- [ ] Build `[%DetailItem.Season{}]` with episodes carrying their own progress + presence + watched-files-count flag. Pre-shape `SeasonView` and `EpisodeListItem` semantics so the existing `DetailPanel.season_section` consumers fall through unchanged once the LiveView assigns are flipped.
- [ ] Build `[%DetailItem.MovieEntry{}]` carrying movie name, date_published, content_url (resolved from PlayableItem.WatchedFile), position (from `Movie.collection_position`).
- [ ] Populate `:watched_files` on each DetailItem with `[%{path, watch_dir, role, file_presence_stamped_at}]`. **Role** is the existing `WatchedFile.role` enum (main / commentary / bonus_disc / etc.).
- [ ] Populate `:subtitle_tracks` either by inlining the existing `Subtitles.list_tracks_for_file/1` query into the projection refresh (one extra query per PlayableItem at refresh time — projection caches it once), or by keeping it as a bulk-overlay (one query at modal open across the leaf set). Decide based on refresh-frequency vs. per-modal-open cost. **Default: inline.** Subtitle tracks are static after detection; per-leaf cost amortises into the cold-start build.
- [ ] Populate `:extra_progress` by joining `Library.WatchProgress` on extras that have at least one `WatchedFile`. Returned as `%{extra_id => WatchProgress.t()}`.
- [ ] Re-emit `:library_view_updated, :detail` on `library:views` for every refresh — this is the unchanged contract from Phase 3 Task B.

**Tests:**
* `test/media_centarr/library/views/detail_test.exs` — add 4 cold-start spec cases (Movie, MovieSeries, TVSeries, VideoObject) verifying each field of the expanded shape against factory fixtures.
* Add 2 incremental-refresh specs: (a) record a new `WatchedFile` → `available_for_ids/1` change reflected in next read; (b) record a `WatchProgress` → progress field updated in next read. Both use `derived-topic-subscribe + receive` per the test-design rules.

**Acceptance:** Projection cold-start populates new fields. Compilation still fails at consumer sites (Task C). `mix test test/media_centarr/library/views/detail_test.exs` green.

---

### Task C — `SeriesDetail.compose/1` reads from projection *(LiveView-layer composition flip)*

**Goal:** TV-series modal entry path stops calling `Library.load_modal_entry/1`. The cross-context overlay (releases, tracking_status, resume target) stays at the LiveView layer; only the Library half flips.

- [ ] Refactor `SeriesDetail.compose/1` to:
  - Call `Library.Views.detail_by_container/2` for the TV series id.
  - Map the returned `DetailItem` + its `:seasons` (typed inner struct) into the existing `SeriesDetail.build/4` inputs. The pure builder stays unchanged — typed input in, typed output out.
  - Continue reading `ReleaseTracking.list_relevant_releases_for_library_container/2` and `lookup_tracking_status/1` exactly as before. The composer's cross-context fetch is preserved.
- [ ] `SeriesDetail.build/4` already accepts a typed library entry — verify the new input shape (DetailItem → entry map) is interface-compatible OR adapt the builder to accept `DetailItem` directly. Prefer the second: the rich-`entity` shape is the legacy compatibility layer we are retiring.
- [ ] Update the in-test factory entry shape consumed by `series_detail_test.exs` to use `DetailItem` directly.

**Tests:**
* `test/media_centarr_web/view_model/series_detail_test.exs` — flip the test factory to construct `%DetailItem{}` fixtures via `build_detail_item/1` (new factory helper). All existing assertions on the `[SeasonView]` output should still pass — the build/4 logic is unchanged, only its input shape moves.
* Verify `compose/1` integration: assert the composer makes zero Repo queries for Library data when the projection is warm.

**Acceptance:** TV-series modal load path reads through the projection. `mix precommit` green. `no_db_on_render_test` for TV-series `/library?selected=<id>` budget drops.

---

### Task D — `Library.load_modal_entry/1` reads from projection *(Movie / MovieSeries / VideoObject flip)*

**Goal:** The non-TV entry path stops calling `Library.Browser.fetch_typed_entries_by_ids/1`. Movie / MovieSeries / VideoObject modal data comes from the projection.

- [ ] Rewrite `Library.load_modal_entry/1`:
  - For Movie/VideoObject: single `Views.detail_by_container/2` read; wrap in the modal entry shape (`%{entity: ..., progress: ..., progress_records: ...}`) using the projection's `DetailItem` + the existing `Library.list_progress_summaries/1` bulk helper from Phase 3.1.
  - For MovieSeries: read each constituent movie's DetailItem via `Views.detail/1` (the projection caches by `playable_item_id`), aggregate into the MovieSeries-level shape. Decision point: does the projection emit one DetailItem per leaf, or one per container? Phase 3 settled on leaf — the consumer aggregates. Confirm consumers still want the MovieSeries-level wrapper or whether the modal can render directly from the constituent-leaf list.
- [ ] `load_extras_for_entity/1` is retired — extras live on the DetailItem now.
- [ ] The "modal entry" wrapper shape (`%{entity, progress, progress_records, tracking_status}`) survives this task; full retirement is Task E.

**Tests:**
* `test/media_centarr/library_test.exs` — `load_modal_entry/1` cases per type. Assert: zero Library Repo queries when the projection is warm (cold-start populates first; test runs against warm projection).
* `test/media_centarr_web/live/library_live_test.exs` — modal-open integration test for Movie + MovieSeries + VideoObject; assert the visible modal fields match the projection output.

**Acceptance:** All four entity types flip. `no_db_on_render_test` budget for `/library?selected=<id>` drops to the Phase 3.1 floor (~5 production queries). `mix precommit` green.

---

### Task E — Retire the wrapper + thin consumer attrs *(boundary cleanup)*

**Goal:** Now that everything reads from the projection, retire the rich-`entity, :map` attrs and pass `DetailItem` directly through the component tree.

- [ ] `DetailPanel`'s `attr :entity, :map` becomes `attr :entity, DetailItem`. Same for `Hero`, `MoreInfoPanel`, `MovieCredits`, `SeriesCredits`. Storybook stories migrate to `%DetailItem{}` literals (same pattern as Phase 3.1's BrowseItem flip).
- [ ] `EntityModal`'s `:selected_entry` assign collapses from `%{entity, progress, progress_records, tracking_status}` to a typed `%MediaCentarrWeb.ViewModel.ModalEntry{}` or similar — TBD whether one or two struct types best capture the variation between TV (with `releases`) and non-TV (without).
- [ ] Delete `Library.load_extras_for_entity/1` (no callers).
- [ ] Delete `Library.load_modal_entry/1`'s rich-shape Browser path (the projection-backed reimplementation from Task D replaces it).
- [ ] Update the `no_db_on_render_test` budgets and the @doc_entity / @doc_progress / @doc_progress_records / @doc_extra_progress_by_id docstrings on `DetailPanel`.

**Tests:**
* No new tests — this task removes legacy paths. All Phase 3.1 + Phase 3.2 tests remain green.
* Verify storybook contract Credo check (MC0009) flags any component that didn't migrate.

**Acceptance:** Rich-`entity` shape is no longer constructed anywhere in the modal flow. `mix precommit` green. The dual-path problem closes — one path through the projection for every entity type.

---

## Open design decisions

These are explicitly *not* decided in this plan — they need a decision at task entry, recorded as a Decision in the Phase 3.2 commit history.

1. **Subtitle tracks: inline on DetailItem or bulk-overlay at modal open?** Default in this plan: inline. Reconsider if cold-start projection build time exceeds the 50ms budget on a 500-entity library.
2. **MovieSeries DetailItem aggregation: per-leaf or per-container?** Phase 3 settled on per-leaf. Phase 3.2 confirms or revisits depending on whether the modal renders MovieSeries differently than a list-of-Movies. Likely confirms per-leaf.
3. **`ModalEntry` struct vs. two separate types (TVModalEntry / MovieModalEntry).** TV carries `releases`; non-TV doesn't. A single struct with a nullable `:releases` field is simpler; two structs are typed-correct. Decide at Task E.
4. **`SeriesDetail.build/4` accepts `DetailItem` directly, or accepts the modal-entry wrapper?** If the wrapper survives Task E, `build/4` keeps its current shape. If the wrapper is retired in Task E, `build/4` accepts `DetailItem` directly and `SeriesDetail` becomes a pure transformation. Recommendation: retire wrapper, simplify.

## Budget targets

* Cold-start projection build time: under 100ms for a 1000-leaf library. Establish baseline via `scripts/profile --rebaseline` at Task B close.
* `/library?selected=<id>` mount queries (test mode): drop from current ~36 (Phase 3.1 floor for the grid + on_mount hook) to the same range (DB-fallback path for the projection in test mode adds ~20 — acceptable, the production cost is what matters).
* `/library?selected=<id>` mount queries (production): drop from current ~10 (Phase 3.1) to ~10 still (the modal-open path is parallel to grid load; both already cheap). Real win is **fewer round trips during modal navigation** — switching between selected items reads from ETS, not the DB.

## Pointers

* `lib/media_centarr/library/views/detail_item.ex` — current shape.
* `lib/media_centarr/library/views/detail.ex` — current projection.
* `lib/media_centarr_web/components/detail_panel.ex` — main consumer.
* `lib/media_centarr_web/components/detail/` — sub-components.
* `lib/media_centarr_web/live/entity_modal.ex` — modal state machine.
* `lib/media_centarr_web/view_model/series_detail.ex` — current TV composer.
* `lib/media_centarr/library.ex` — `load_modal_entry/1` + `load_extras_for_entity/1`.
* `test/media_centarr_web/no_db_on_render_test.exs` — budget guard.

## Out of scope

* `Library.Views.Search` consumer flip — separate Phase 3 follow-up (decision pending on per-leaf vs. entity-only).
* ReleaseTracking projection for the modal's "future seasons" panel — would be premature; the current `list_relevant_releases_for_library_container/2` call is cheap and already cached at the LiveView layer.
* Playback session projection — already paradigm-correct ([ADR-041](../../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md)).
