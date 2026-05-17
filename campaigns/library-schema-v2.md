---
status: phase-3.2-in-progress
started: 2026-05-15
last_updated: 2026-05-17c
---
# Library Schema v2 — architectural excellence

## Goal

Redesign the Library bounded context's data model from first principles
now that we know how it's used. The current schema works but carries
structural debt that will compound the longer it lives: a 5-FK
polymorphic fanout across every supporting table, stringly-typed
domain values, a `Movie` schema serving two distinct roles, and a
runtime denormalization layer (`EntityShape.normalize/3`) papering
over the fact that the leaves don't share a schema.

No users exist yet — destructive migrations are free. We take the
shape we'd choose today and ship it, then we can ride it into a public
release with confidence that the foundation is right.

This campaign sits **alongside** [`desktop-rearchitecture.md`](desktop-rearchitecture.md):
- Desktop-rearchitecture moves *reads* from Pillar 1 (DB) to Pillar 2
  (ETS projections) per [ADR-041](../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md).
- This campaign rebuilds the *Pillar 1 schema* the projections rebuild
  from. The cleaner the schema, the cleaner the projection layer feeding
  off it.

The phases interleave: schema redesign first (Pillar 1 right shape),
projection fan-out second (Pillar 2 expansion to remaining LiveViews).

## Status

**Phase 1 — Foundation cleanup: ✅ complete (2026-05-16).** Six
landed commits on top of `36fd51f2`:

| Task | Commit | Change |
|------|--------|--------|
| 1 | `ypxmwrvw` | `refactor(library): type cast/crew via Library.Person embedded schema` |
| 2 | `tqpqwvxu` | `refactor(library): type date_published as :date` |
| 3 | `tvmykywt` | `refactor(library): canonicalise duration as integer seconds` |
| 4 | `lqnxnzvp` | `feat(library): MovieSeries metadata symmetry with TVSeries` |
| 5 | `uuszztpt` | `refactor(subtitles): own subtitle_tracks table; drop WatchedFile.subtitle_tracks` |
| 6 | `nomwwwuk` | `refactor(library): ExternalId is sole source for TMDB/IMDB ids` |

Each landed via dispatch-implement-review-fix loop. Full precommit
green at every commit boundary. `mix test` stable at 3386 tests, 0
failures.

**Phase 2 — PlayableItem reification: ✅ complete (2026-05-16).**
Detailed plan at [`docs/superpowers/plans/2026-05-16-library-schema-v2-phase2.md`](../docs/superpowers/plans/2026-05-16-library-schema-v2-phase2.md).
Nine landed commits on top of Phase 1:

| Task | Commit | Change |
|------|--------|--------|
| A | `mpnwlrkx` | `feat(library): introduce PlayableItem as the canonical leaf` |
| B | `vptkvqyu` | `refactor(library): refit WatchedFile to playable_item_id; introduce ExtraFile for Extras presence` |
| C | `mzuowyyw` | `refactor(library): refit WatchProgress to single playable_item_id` |
| D+E+F | `yskspyxw` | `refactor(library): polymorphic owner discriminators on Image, Extra, ExternalId` (3 tables in one combined dispatch) |
| G | `rnuumrqv` | `refactor(library): Inbound writes PlayableItem rows for every leaf ingest` |
| H | `ukvmpnmk` | `refactor(library): TypeResolver/EntityShape/EntityCascade pivot on PlayableItem` |
| I | `tkpxnspm` | `refactor(library): drop content_url from Movie/Episode/VideoObject; WatchedFile is sole file source` |
| J | `yqtomypk` | `refactor(release_tracking): library_entity_id → library_container_id with discriminator` |

Each landed via dispatch-implement-review-fix loop. `mix precommit`
green at every commit boundary. Stats: 3386 → 3433 tests, 0 failures
throughout. `EntityShape.normalize/3` deleted; `WatchedFile.owner_id/1`
deleted; the 3–5-FK polymorphic fanout collapsed to a single FK or a
single `(owner_type, owner_id)` discriminator on every supporting
table. `PlayableItem` is the canonical leaf — director's cuts and
multi-part episodes are schema-representable (not yet UI-exposed).

Notable mid-flight finding: Task B's migration on production-shape
data found 22 collection-level WatchedFiles (bonus features attached
to MovieSeries) that the new schema couldn't host as PlayableItems.
User chose the architectural fix — new `Library.ExtraFile` schema
parallel to WatchedFile, preserving file-presence for Extras without
inventing a fake leaf. Folded into Task B's commit.

**Phase 3 — Library projection fan-out: ✅ complete (2026-05-16).**
Detailed plan at [`docs/superpowers/plans/2026-05-16-library-schema-v2-phase3.md`](../docs/superpowers/plans/2026-05-16-library-schema-v2-phase3.md).
Five landed commits on top of Phase 2:

| Task | Commit | Change |
|------|--------|--------|
| A | `myopmstx` | `feat(library): Views.Browse projection — LibraryLive reads in microseconds` |
| B | `yrrtpzko` | `feat(library): Views.Detail projection — per-PlayableItem read in microseconds` |
| C | `slxsnvrq` | `feat(library): Views.Search in-memory entity index` (with `present?` honesty fix squashed) |
| D | `ykzvpqqu` | `feat(library): Progress Pillar-2 GenServer with debounced flush` (with batched-flush + doc fixes squashed) |
| E | `ltppnnqq` | `refactor(web): retire DB-on-render reads; close progress stale-read window` |

Each task landed via dispatch-implement-review-fix loop with **automated-testing rigor as the explicit bar.** `mix precommit` green at every commit boundary. Stats: 3433 → 3567 tests, 0 failures throughout.

**Architectural deliverables:** four ADR-041 projections (Browse, Detail, Search, plus the pre-existing ContinueWatching et al.) live behind `Library.Views.*`; Library.Progress is a Pillar-2 GenServer with debounced 5s flush, in-memory ETS reads, terminate-time flush, boot-time hydration; the `no_db_on_render_test` locks the per-LiveView Repo-query budget in place; the I-2 stale-read window closed via `overlay_in_memory_progress/1` in `ProgressBroadcaster` and `Library.list_in_progress`.

**Scope honesty:** the marquee "LibraryLive grid reads from Views.Browse" was deliberately deferred (see Phase 3 follow-ups). BrowseItem / SearchItem / DetailItem are minimal projections by design (ADR-041 — "compose at the consumer"); the LiveViews currently consume richer entry shapes (progress, resume_target, extras, per-card playing?). Migrating wholesale requires expanding the projection schemas to carry those fields, which is a non-trivial second pass on each projection. Today's deliverables: the projections are operational and tested; the LiveViews already read through context functions (no raw `Repo`); the query-counter test pins the architecture in place. The cosmetic "every LiveView calls `Views.*`" is a follow-up.

## Phase 1 follow-ups

Items surfaced during Phase 1 reviews and deferred — not blocking
Phase 2 but worth picking up for full architectural polish:

- **Year-helper consolidation** (Task 2). Today's codebase has 4+
  year-extraction helpers: `Format.year/1` (Date-only),
  `LibraryFormatters.extract_year/1` (Date + binary + nil),
  `Logic.year_from_date/1` (Date + binary + nil + ""), plus private
  clones in `release_tracking.ex` and `tmdb/confidence.ex`. The
  binary-tolerance clauses exist for storybook fixtures that haven't
  migrated to typed `%Date{}` fixtures yet (component-contract
  campaign). Once those migrate, collapse to single canonical helper.

- **`Subtitles.list_tracks_for_file/1` ordering determinism** (Task 5).
  Order-by uses `[asc: inserted_at, asc: id]` — UUID random + second-
  resolution timestamps means within-second insertion order is lost.
  No current consumer depends on it; if a future read needs
  deterministic order, add an explicit `:position` column or sort by
  `:source`/`:language` as secondary key.

- **`refresh_movie_series_credits/0` skip predicate** (Task 4).
  Currently a no-op data-wise (collection responses don't carry
  credits); the driver's `cast != [] and crew != []` skip clause
  never engages because every fetch returns `[]`. Either implement a
  `last_credits_fetched_at`-based predicate, OR aggregate constituent
  movie credits up to the collection level. Out of scope for Phase 1.

- **Migration reversibility note in CHANGELOG** (Task 5). The
  subtitles-table migration's rollback drops detected track data.
  Note when v0.62 ships.

- **Showcase subtitle seeding** (Task 5). `priv/showcase/media-centarr.db`
  has the `subtitles_tracks` table but no rows — seed needs to either
  invoke detection on seeded files or hard-code fixtures so the
  showcase demonstrates subtitle UI.

- **`format_runtime/1` duplication observation** (Task 2 review).
  More duplication may exist in less-trafficked render paths; full
  consolidation deferred until Phase 2/3 read-model unification, when
  the canonical view-model struct will absorb formatting too.

## Phase 2 follow-ups

Items surfaced during Phase 2 reviews — not blocking Phase 3:

- **`populate_leaf_content_url/1` silent-nil → raise on
  NotLoaded** (Task I review). The `content_url` virtual field is
  silently nil when `playable_items` isn't preloaded; convert to a
  loud `ArgumentError` so the next contributor sees the
  missing-preload bug at test time, not runtime.
- **Multi-PlayableItem `content_url` ordering policy** (Task I).
  `populate_leaf_content_url/1` uses `Enum.find_value` — order is
  whatever Repo returned. Add `order_by: [asc: position]` on the
  preload (or document the non-determinism explicitly).
- **`StatusHelpers.progress_matches_session?/2`** (Task C). Compares
  `progress.playable_item.container_id` against `now_playing[:movie_id]`
  etc., but `MpvSession.build_now_playing/1` doesn't populate those
  keys. Pre-existing latent bug, surfaced by Task C. Either backfill
  the keys at session start or rewrite the helper to use
  `now_playing.entity_id`.
- **`MpvSession` FK-key deferral** (Task C). Session-state still
  carries `movie_id` / `episode_id` / `video_object_id`; only the
  persistence boundary migrated. Worth a follow-up if a future task
  needs the playable_item_id internally during a session.
- **`has_one through` silent drop on multi-cut** (Task C). When a
  Movie has multiple PlayableItems with progress, `Repo.preload(movie,
  :watch_progress)` silently returns the first row instead of raising.
  Acceptable today (no multi-cut writers); tighten when multi-cut UI
  ships.
- **EntityCascade `bulk_destroy` ordering comment** (Task H). Cascade
  order is correct but the relationship between `destroy_leaf!` and
  `bulk_destroy` is implicit; one inline comment removes the trap.
- **`Library.find_or_create_external_id/1`** (D+E+F review). Helper
  looks up by `(source, external_id)` only — could return a row owned
  by a different `owner_type` than requested. Currently has zero
  callers (orphan helper). Either remove or fix to include
  `owner_type` in the lookup.
- **TMDB `Mapper` image helpers still emit legacy `entity_id` keys**
  (D+E+F). No live consumers (only tests); remove when those tests
  refactor.
- **`resources_in_delete_order` missing PlayableItem** (D+E+F note).
  `Maintenance.resources_in_delete_order/0` doesn't list PlayableItem;
  Task H rewrote the cascade so this is no longer load-bearing, but
  the constant could be deleted entirely if nothing else reads it.
- **Validate-pair test for `release_tracking_items`** (Task J). 5-line
  test for the half-set rejection of `validate_container_pair/1`.
- **`ComingUpItemRef.entity_id` discoverability comment** (Task J). The
  view-model field is named `entity_id` but holds a Library container
  UUID — kept for URL-param convention. One-line `@doc` removes the
  ambiguity.
- **`StatusResolver.progress_record_key/1` simplification** (Task C
  follow-up review). Now keys by `playable_item_id` only — verify no
  edge case where the legacy tuple-key invariant mattered.

## Phase 3.1 — LibraryLive cutover (✅ shipped 2026-05-16)

Three-commit landing of the previously-deferred Task E I-4
("LibraryLive grid → Views.Browse"). Resolved by **keeping
BrowseItem minimal per ADR-041** rather than expanding the projection
shape: progress and availability moved to dedicated bulk context
functions consumed alongside the projection at the LiveView layer.

- **Commit 1 — `feat(library): BrowseItem carries date_published; Browse ranks by inserted_at desc`**
  - `BrowseItem` gains `:date_published` (full `%Date{}`); `:year` stays as the cheap cached read for the poster card.
  - The projection's canonical order flips from alpha to `inserted_at desc` — the recent-first "what did I just add?" default.
  - `Library.Browser.fetch_all_typed_entries/0` gains a `:sort` opt (`:recent` default, `:alpha` retained).
- **Commit 2 — `feat(library): bulk progress summaries + availability lookups for projection consumers`**
  - `Library.list_progress_summaries/1` — kind-grouped bulk progress reader returning `%{entity_id => summary}` with `:last_watched_at` extended into the summary shape.
  - `Library.Availability.available_for_ids/1` — bulk availability lookup keyed by container UUID; one query per container kind, totals don't scale with row count.
- **Commit 3 — `feat(library): LibraryLive grid reads from Views.Browse projection`**
  - LibraryLive's grid now reads `Views.browse()` + the two bulk helpers; subscribes to `library:views`.
  - `LibraryHelpers`, `LibraryProgress`, `LibraryAvailability`, and `poster_card` migrated to the `BrowseItem` + `progress_by_id` shape.
  - Storybook story rewritten against `%BrowseItem{}` literals so the typed-coupling check (MC0009) keeps the new contract honest.

**Budget achieved:** `/library` mount issues ~36 queries in test mode
(DB fallback for the projection — Cache.Worker isn't running) and
~10 in production (microsecond ETS lookup + ~6 bulk queries + ~4
on_mount-hook cache-miss reads). The test-mode budget moved from 80
to 45 to reflect the fallback path; the production benefit is the
ETS lookup, not the test-mode count.

## Phase 3.2 — DetailLive cutover (🚧 in progress, started 2026-05-17)

Apply the Phase 3.1 pattern (projection + bulk-helper overlays) to
the entity-detail modal. Plan doc:
[`docs/superpowers/plans/2026-05-17-library-schema-v2-phase3.2-detail-cutover.md`](../docs/superpowers/plans/2026-05-17-library-schema-v2-phase3.2-detail-cutover.md).

Five tasks (A → E); four landed today:

- **Task A — DetailItem typed inner structs** (commit `e07ab5d7`, 2026-05-17).
  `DetailItem.{Season, Episode, MovieEntry, WatchedFile, SubtitleTrack}`
  inner modules + `:images, :seasons, :movies, :watched_files,
  :subtitle_tracks` on DetailItem. Design decision recorded:
  per-episode progress is overlay (`Library.Progress.get/1`), not
  embedded — playback ticks must not invalidate the projection.

- **Task B — Projection populates the new fields** (commit `7f1be81a`, 2026-05-17).
  `Views.Detail.refresh_cache/0` extended: PlayableItems grouped by
  top-level entity, entity-level shared data (`:images, :seasons,
  :movies`) built once per group (functional sharing). Per-leaf
  `:watched_files, :subtitle_tracks` per row. `read_by_container/2`
  extended for `:tv_series` + `:movie_series` (canonical-leaf lookup).
  `top_level_container/2` extended for Movies under MovieSeries
  (mirror of Episode → TVSeries).

- **Task C.1 — DetailItem.Episode/Season grow content_url + number_of_episodes + extras** (commit `3f242e9e`, 2026-05-17).
  Prep for the SeriesDetail.compose flip. Episode's `:content_url`
  from first WatchedFile; Season's `:number_of_episodes` from schema;
  Season's `:extras` populated from preloaded Extra rows. No
  consumer reads yet — splits the C work into prep + flip.

- **Task C.2 — SeriesDetail.compose/1 reads from projection** (commit `8d5dd0f7`, 2026-05-17).
  TV-series modal-open path flipped: `Library.Views.detail_by_container(:tv_series, _)`
  + new `DetailItem.to_entity_map/1` adapter (pure, TV-only, retires
  in Task E) + new `Library.list_progress_records_for_tv_series/1`
  (replaces the `EntityShape.extract_progress` walk over a preloaded
  entity). Reused `ProgressSummary.compute/2`. The `:not_found` vs.
  `{:error, :wrong_type}` distinction preserved via a `TypeResolver`
  fallback when the projection returns nil. Page-smoke surfaced a
  per-episode-image render gap, fixed in the same commit by growing
  `DetailItem.Episode` with `:images` (default `[]`) and batch-loading
  them in `build_seasons_for_tv_series`. `mix precommit` green (3617
  tests, 0 failures). Existing `series_detail_test.exs` `compose/1`
  cases pass unchanged.

Tasks remaining:

- **D — Flip Library.load_modal_entry to projection.** Movie /
  MovieSeries / VideoObject modal-open paths.
- **E — Retire rich-entity-map attrs.** DetailPanel + sub-components
  consume `DetailItem` directly. Adapter from C.2 deleted.

## Phase 3 follow-ups

Items surfaced during Phase 3 reviews — the marquee deliverables are
shipped; these are the deliberate deferrals worth picking up next.
- **Library search → `Library.Views.search/2`** (Task C E.2 deferral).
  `library_helpers.ex` `filtered_by_text/2` substring-matches against
  nested season/episode/movie names. The Views.Search projection is
  entity-level today. Routing requires deciding whether to broaden
  Search to per-leaf rows (better UX, larger index) or accept
  entity-only matching (simpler, regresses the side-effect-y nested
  search). Decision should follow user behaviour data, not a guess.
- **DetailLive / EntityModal → `Library.Views.detail/1`** (Task E E.3
  deferral). `DetailItem` doesn't yet carry the full file / season /
  episode tree the modal renders. Same trade-off as Browse: expand the
  projection shape (preferred — single ETS lookup at modal open) or
  keep the existing `TypeResolver + Repo.preload` path.
- **`reset_for_test!/0` Mix.env guard** (Task D review M-1). The
  public function is doc-tagged as test-only but not enforced. Add a
  release-time guard if/when we ship a hardened release where the
  surface needs to be locked down.
- **Cache.handle_message/1 partial-refresh path direct test** (Task B
  review I-1, not yet addressed). The partial-refresh
  `Cache.Worker` callback added in Task B is exercised end-to-end via
  Detail tests but lacks a direct unit test. Worth adding one in
  `cache_test.exs` so future contributors don't regress the callback
  signature.
- **`Library.playable_item_ids_for_entities/1` UNION** (Task B
  review I-2, not yet addressed). Three sequential `Repo.all/1` calls
  could collapse to a single UNION query. Marginal at current sizes;
  worth doing when batched cascade ops surface as a hot path.
- **Browse projection `present?` could be derived honestly** (Task C
  fix-up note). Browse uses Browser as source which pre-filters to
  presentable entities; same tautology Search had. Either expose a
  presence-agnostic Browse source so the projection can compute
  `present?` per-row, or accept that `present?` on `BrowseItem` is
  always `true` for as long as Browser stays the source.
- **Browse projection ETS cache in test mode** (Phase 3.1 follow-up).
  The Cache.Worker isn't started in tests, so `Views.browse/0`
  falls back to a fresh `Browser.fetch_all_typed_entries/0` build —
  that pumps `/library` mount budget up to ~36 queries in test mode
  versus ~10 in production. A `setup`-block `Cache.Worker.refresh/1`
  for tests would let the budget rule actually pin the production
  count; today's 45-query test ceiling tolerates the fallback. Wire
  it once the patterns stabilise across the other projections.
- **Library filter `nested season/episode search` removed in 3.1**
  (Phase 3.1 follow-up). `LibraryHelpers.filtered_by_text/2` used to
  walk `entity.seasons/episodes` and match episode titles. BrowseItem
  doesn't carry that data; the helper now matches only on
  `BrowseItem.name`. Routing nested-text matches through
  `Library.Views.search/2` is the long-term fix (entity-level vs
  per-leaf rows is a UX call); for now, users with nested filter
  habits will need the search projection.

## Architectural premises

These are the load-bearing assumptions every decision rests on. Call
them out if any change.

1. **Local desktop app — statefulness is an asset.** Reads live in
   BEAM processes (ETS / `:persistent_term`); the DB is the durable
   write side. Thin LiveViews subscribe to projections, never query
   Pillar 1 directly on the render path. Established by ADR-041; this
   campaign relies on it.
2. **SQLite is the durable store.** Single writer, fast local reads,
   no network. Storage cost of a redesign is one `mix ecto.reset`.
3. **No backwards compatibility required.** No deployed users. Every
   migration may be destructive. Showcase + dev DBs rebuild from
   scratch via existing seed paths.
4. **TMDB is the canonical external source.** Every entity worth
   tracking has a TMDB row. IMDB / TVDB are secondary identifiers.
5. **The user-visible playable unit is "press play and watch".**
   That's the leaf — movie, episode, movie-series-child, video-object
   are the four ways the same concept (a thing with a file, a
   duration, and watch progress) manifest in the UI.

## Target schema

The end state we are building toward.

### Containers (metadata holders)

Each container schema carries TMDB-derived metadata. None of them
carry `content_url`, watch progress, or watched_files directly —
those live on the leaf (`PlayableItem`).

| Schema | Table | Holds |
|--------|-------|-------|
| `Movie` | `library_movies` | Standalone movie metadata or series-child movie metadata. Nullable `movie_series_id`. |
| `TVSeries` | `library_tv_series` | TV series metadata. `has_many :seasons`. |
| `Season` | `library_seasons` | Season metadata. `has_many :episodes`. |
| `Episode` | `library_episodes` | Per-episode metadata (description, runtime). `has_many :playable_items`. |
| `MovieSeries` | `library_movie_series` | Movie collection metadata. `has_many :movies`. Symmetric with `TVSeries` on cast/crew/tagline/studio/etc. |
| `VideoObject` | `library_video_objects` | Standalone video metadata. |

### The leaf — `PlayableItem`

```elixir
schema "library_playable_items" do
  field :container_type, Ecto.Enum, values: [:movie, :episode, :video_object]
  field :container_id, Ecto.UUID
  field :position, :integer          # episode number / series position / 1 for solo
  field :duration_seconds, :integer  # canonical, integer, never string
  field :name, :string               # override / version label (e.g. "Director's Cut")

  has_many :watched_files, Library.WatchedFile
  has_one :watch_progress, Library.WatchProgress
  has_many :subtitle_tracks, Library.SubtitleTrack
  has_many :images, Library.Image, where: [owner_type: :playable_item]

  timestamps()
end
```

**The win:** every supporting table collapses from a 3–5-FK fanout to
a single FK. `WatchedFile`, `WatchProgress`, `SubtitleTrack` all key
to `playable_item_id` only. `Image` and `Extra` polymorphism reduces
to a single `(owner_type, owner_id)` pair.

**The unlock:** one container can have N playable items, naturally.
A Movie with theatrical + director's cut versions is two
`PlayableItem`s pointing at the same `Movie`. A two-part episode is
two `PlayableItem`s pointing at the same `Episode`. Today's schema
can't represent either.

**The "movie-series-child" question:** there is no separate kind. A
movie-series child is a `Movie` row with `movie_series_id` set, plus
its `PlayableItem` of `container_type: :movie`. Whether the movie is
standalone or in a series is data on `Movie`, not on `PlayableItem`.

### Supporting tables (single-FK, polymorphism-once)

| Schema | Owner | Notes |
|--------|-------|-------|
| `WatchedFile` | `playable_item_id` | Single FK. File path, watch_dir. Subtitle tracks moved out. |
| `WatchProgress` | `playable_item_id` | Single FK. Position, duration, completed, last_watched_at. No more `(season=0, episode=0)` overload. |
| `SubtitleTrack` | `watched_file_id` | New table. Kind, language, source. Owned by `Subtitles` context (table named `subtitles_tracks`). |
| `Image` | `owner_type` + `owner_id` | Single discriminator. Owner types: `:movie`, `:tv_series`, `:movie_series`, `:video_object`, `:episode`, `:playable_item`. App-level integrity. |
| `Extra` | `owner_type` + `owner_id` | Same pattern. Owner types: `:movie`, `:tv_series`, `:movie_series`, `:season`. |
| `ExternalId` | `owner_type` + `owner_id` | Same pattern. Sole source of truth for TMDB/IMDB IDs — drop the redundant columns from container schemas. |

**On discriminators vs FK enforcement:** we lose SQLite's FK
enforcement for the polymorphic tables (Image, Extra, ExternalId).
The tradeoff: a single owner column is mechanically simpler and a new
owner type adds one enum value instead of one nullable FK per table.
We accept app-level integrity here because (a) writes always go
through `Library.Inbound` or context functions, (b) the existing 5-FK
shape has no DB-level "exactly one set" constraint either, so we're
not losing anything we had. Cascade deletes get rewritten as explicit
context-level cascades (which they already are — see `EntityCascade`).

### Typed fields throughout

| Today | Tomorrow | Why |
|-------|----------|-----|
| `date_published :string` | `:date` | Sorts, filters, comparisons cease to need parse-on-every-read. |
| `duration :string` ("PT1H30M") | `duration_seconds :integer` | Native arithmetic; no parse roundtrips. |
| `tmdb_id :string` on containers | (removed; sole row in `ExternalId`) | One source of truth. |
| `imdb_id :string` on containers | (removed; sole row in `ExternalId`) | One source of truth. |
| `cast {:array, :map}` | `embeds_many :cast, Library.Person` | Typed contract: `name`, `character`, `order`, `profile_path`. |
| `crew {:array, :map}` | `embeds_many :crew, Library.Person` | Typed contract: `name`, `job`, `department`, `profile_path`. |
| `subtitle_tracks {:array, :map}` on `WatchedFile` | own table, `Subtitles.Track` | Cross-context data in another context's table is a smell. |

### What stays

- UUID primary keys.
- Type-specific container tables (the polymorphism failure of the old
  unified `library_entities` table is not what we're un-doing).
- `Library.Inbound` as the single write entry point from the pipeline.
- `Library.FileEventHandler` cleanup cascade.
- `Library.Availability` watch-dir reachability tracking.
- All existing projections (`ContinueWatching`, `HeroCandidates`,
  `RecentlyAdded`). They get re-pointed at new context functions but
  the pattern is unchanged.

## Phases

### Phase 1 — Foundation cleanup *(no structural changes)*

Independent fixes that don't touch the polymorphic fanout. Land first
because they're low-risk and reduce the surface area Phase 2 touches.

| # | Change | Touch points |
|---|--------|--------------|
| 1 | `Library.Person` embedded schema; `Movie`/`TVSeries`/`MovieSeries` use `embeds_many :cast, Person` / `embeds_many :crew, Person` | 3 schemas, `Library.Inbound`, TMDB mappers, factory, UI templates that render cast |
| 2 | `date_published` becomes `:date` everywhere | 4 schemas, changesets, `Format` helper, all templates that display year |
| 3 | `duration` becomes `duration_seconds :integer` everywhere it appears | `Movie`, `Episode`, `Format.duration/1`, TMDB mappers |
| 4 | `MovieSeries` gains metadata symmetry with `TVSeries`: `tagline`, `original_language`, `studio`, `country_code`, `status`, `cast`, `crew`, `vote_count` | `MovieSeries` schema + migration; `Library.Inbound` `movie_series_attrs/1`; TMDB collection mapper |
| 5 | Move `subtitle_tracks` out of `WatchedFile` into `Subtitles.Track` (table `subtitles_tracks`) under the `Subtitles` context | new schema/migration, `WatchedFile`, `Subtitles` context, `Playback` reads |
| 6 | Drop `tmdb_id` and `imdb_id` columns from all container schemas; ExternalId rows are sole source. Add `Library.ExternalIds.put(:tmdb \| :imdb, owner, id)` helper. | 4 schemas, `Library.Inbound`, `TypeResolver.find_by_tmdb_id/1`, every caller of `record.tmdb_id` |

Detailed Phase 1 implementation plan:
[`docs/superpowers/plans/2026-05-15-library-schema-v2-phase1.md`](../docs/superpowers/plans/2026-05-15-library-schema-v2-phase1.md).

**Completion:** all of the above shipped, `mix precommit` green, all
projections regenerate against the new shape, showcase rebuilds clean.

### Phase 2 — `PlayableItem` reification *(the structural shift)*

The load-bearing change. Introduces `PlayableItem` as the leaf and
re-wires every supporting table to it.

#### Tasks

1. **Define `Library.PlayableItem` schema + migration.**
   - `library_playable_items` table with `container_type` /
     `container_id` / `position` / `duration_seconds` / `name`.
   - `container_type` enum: `:movie | :episode | :video_object`.
2. **Define `Library.Image` polymorphic shape.**
   - Drop `movie_id` / `episode_id` / `tv_series_id` /
     `movie_series_id` / `video_object_id` columns.
   - Add `owner_type` (enum) / `owner_id` (uuid).
   - Compound unique index `(owner_type, owner_id, role)`.
3. **Define `Library.Extra` polymorphic shape.**
   - Same transform: discriminator + uuid.
   - Owner types: `:movie | :tv_series | :movie_series | :season`.
4. **Define `Library.ExternalId` polymorphic shape.**
   - Same transform: discriminator + uuid.
   - Owner types: `:movie | :tv_series | :movie_series | :video_object`.
   - Unique index `(source, external_id, owner_type)`.
5. **Refit `WatchedFile`.**
   - Drop `movie_id` / `tv_series_id` / `movie_series_id` /
     `video_object_id` columns.
   - Add `playable_item_id` FK.
   - `WatchedFile.owner_id/1` (the FK-coalescer) deletes — it's just
     `wf.playable_item_id` now.
6. **Refit `WatchProgress`.**
   - Drop `movie_id` / `episode_id` / `video_object_id` columns.
   - Add `playable_item_id` FK (unique — one progress per
     playable_item).
   - Doc note on `(season=0, episode=0)` overload deletes.
7. **Refit `Subtitles.Track`.**
   - From "FK to WatchedFile" to "FK to PlayableItem" if needed (more
     natural — subtitles are about the playable thing, not the
     particular file).
   - Decision: keep on WatchedFile in Phase 1; revisit in Phase 2 only
     if a use case emerges.
8. **Migrate `Library.Inbound` to create `PlayableItem` rows.**
   - Movie ingest: create Movie + PlayableItem.
   - Episode ingest: create Episode + PlayableItem.
   - VideoObject ingest: create VideoObject + PlayableItem.
   - MovieSeries-child ingest: create Movie (with `movie_series_id`)
     + PlayableItem.
9. **Update `Library.TypeResolver`.**
   - `resolve/1` now resolves by PlayableItem id → returns
     `{:ok, kind, playable_item, container}`.
   - Container-by-id lookup (the rarer case) gets a separate function.
10. **Delete `Library.EntityShape.normalize/3`.**
    - `PlayableItem` *is* the normalized shape. Every caller of
      `normalize/3` re-targets to `PlayableItem` + preloaded
      container.
11. **Rewrite `Library.EntityCascade`.**
    - Cascade deletion runs `playable_items → watched_files →
      watch_progress → subtitle_tracks → images → extras →
      external_ids → container`.
12. **Drop `content_url` from `Movie`, `Episode`, `VideoObject`.**
    - File path lives only on `WatchedFile.file_path`. UI reads
      "playable item with at least one present WatchedFile" instead.
13. **Drop legacy `library_entity_id` columns from `release_tracking`
    and `acquisition_*` tables.**
    - Replace with `playable_item_id` where the reference is to a
      playable thing, or `container_type` + `container_id` where the
      reference is to a container (TVSeries / MovieSeries).

#### Phase 2 risk hot-spots

- **`Library.Inbound` is the integration linchpin.** Its tests
  exercise the full pipeline → Library handoff. Plan: rewrite
  Inbound's mapper functions, expand its tests to cover the new
  PlayableItem branch, and use `--repeat-until-failure 50` to flush
  flakes.
- **Cascade ordering.** SQLite's FK enforcement bites if order is
  wrong. Write a dedicated `entity_cascade_test.exs` that destroys
  one of each kind and asserts row counts pre/post.
- **The 4 existing ETS projections** all preload by entity type
  today. They'll need re-pointing at `PlayableItem`-shaped reads.
  Baseline-diff after re-pointing — read perf should be equal or
  better, since the projection reads from in-memory pre-shaped
  structs anyway.

**Completion:** `EntityShape.normalize/3` deleted; `TypeResolver`
operates on PlayableItem; `WatchedFile.owner_id/1` deleted;
`mix precommit` green; all four projection baselines stable across
three consecutive runs.

### Phase 3 — Library projection fan-out *(Pillar 2 expansion)*

Feeds into [`desktop-rearchitecture.md`](desktop-rearchitecture.md)
Workstream A. With the schema clean, every remaining DB-on-render
path gets its own ETS projection.

#### Remaining read paths to project

| Page | Today | Tomorrow |
|------|-------|----------|
| `LibraryLive` (browse) | `Library.Browser.list/2` on render | `Library.Views.Browse` ETS projection, keyed by display order, filterable view-side |
| `DetailLive` (modal) | `TypeResolver.resolve + Repo.preload` on open | `Library.Views.Detail` keyed by playable_item_id; covers one PlayableItem with its container + supporting data |
| Search results | Ad-hoc `where ilike` | `Library.Views.Search` — full index in memory (sub-10ms for 10K entries with a simple Jaro/contains scan) |
| Watch progress (active playback) | Per-tick DB write | `Library.Progress` (Pillar 2 GenServer) — in-memory progress with debounced 5-second writes to DB |

#### Tasks

1. **`Library.Views.Browse` projection** — list of all containers,
   denormalized for browse grid rendering. Refresh on
   `library:updates`.
2. **`Library.Views.Detail` projection** — one row per PlayableItem,
   with container + supporting data inlined. Refresh on
   `library:updates`. `DetailLive` reads in a single `:ets.lookup`.
3. **`Library.Views.Search` projection** — flat in-memory index of
   `{playable_item_id, search_text, kind}`. Search runs `Enum.filter`
   on the ETS table (10K entries is microseconds).
4. **`Library.Progress` Pillar 2 GenServer** — owns current playback
   position; LiveView reads/subscribes to it; periodic flush to
   `library_watch_progress`. On boot, hydrates from DB.
5. **Retire DB-on-render reads.** Every LiveView mount checks: does
   it hit `MediaCentarr.Repo` directly? Move to a projection.

**Completion:** `grep -r "Repo\\." lib/media_centarr_web/live` returns
zero hits on read paths; every projection has a baseline; all four
new projections + Phase 2's re-pointed existing ones diff-stable
across three consecutive `scripts/profile` runs.

## Decisions made

Append-only. Recorded as we go.

* `2026-05-15` — **Discriminator + UUID for cross-cutting
  polymorphism** (Image, Extra, ExternalId). The "exactly one FK
  set" multi-column approach is the symptom we're fixing; we don't
  reproduce it on the new tables. App-level integrity at the write
  seam (Inbound, context functions); cascade ordering covered by
  EntityCascade tests.
* `2026-05-15` — **PlayableItem keys to container by
  `(container_type, container_id)`** rather than four nullable
  belongs_to columns. Same reasoning as above; consistency with the
  rest of the polymorphic supporting tables.
* `2026-05-15` — **`Movie` is the schema for both standalone and
  series-child movies.** A series-child Movie is a `Movie` with
  `movie_series_id` set. Reasoning: TMDB returns full movie metadata
  for collection members; collapsing them into bare PlayableItems
  would discard cast/crew/studio. The "kind discriminator" lives on
  PlayableItem (always `:movie` for these) and the parent-or-not
  distinction lives on Movie.
* `2026-05-15` — **No backwards compatibility, destructive
  migrations OK.** User confirmed no deployed users; this campaign
  treats `mix ecto.reset` as a normal developer operation.
* `2026-05-15` — **Phase 3 feeds desktop-rearchitecture Workstream
  A.** Rather than starting a third campaign for the projection
  fan-out, we extend the existing one. The schema redesign is the
  prerequisite that makes the projection layer cleaner.
* `2026-05-15` — **Container schemas are metadata-symmetric by default.**
  If you add a field to TVSeries (cast, crew, status, tagline, etc.), add
  it to MovieSeries too unless TMDB cannot expose it at the collection
  level. Use `nil` defaults for fields TMDB doesn't provide today; the
  schema being ready is more valuable than the field being populated.
  Movie's per-row metadata also stays consistent across standalone vs
  series-child rows.

## Open questions

These need resolution before / during the phase that touches them.

* **Q1 — Subtitles ownership.** `Subtitles.Track` keys to
  `WatchedFile.id` (Phase 1) or to `PlayableItem.id` (Phase 2)? A
  single PlayableItem may have multiple WatchedFiles (drives that
  come and go) and the subtitle tracks belong to the *file*, not the
  playable thing. **Lean:** keep on WatchedFile. Decide at start of
  Phase 1 sub-task 5.
* **Q2 — Migration mechanics in dev.** Do we keep additive
  migrations through Phase 1+2 (so `mix ecto.migrate` works without
  reset), or do we ship one big "drop and recreate" migration since
  there are no users? **Lean:** additive migrations, because the
  showcase and dev DBs do have data the developer doesn't want to
  manually re-create on every pull. Cost is a handful of more
  migration files; benefit is `mix ecto.migrate` keeps working.
* **Q3 — Episode multi-file support.** Should Phase 2 actually allow
  multiple PlayableItems per Episode (e.g. multi-part episodes), or
  just enforce 1:1 today and unlock it later? **Lean:** allow N:1 in
  the schema (it's free), keep ingest writing 1:1, add a UI feature
  later when actual multi-part content shows up. No code cost,
  removes a future migration.

## Completion criteria

- Every container schema (Movie, TVSeries, MovieSeries, VideoObject)
  carries only metadata; no `content_url`, no `tmdb_id`, no
  `imdb_id`, no `subtitle_tracks`.
- `PlayableItem` is the leaf. Every supporting table (WatchedFile,
  WatchProgress, SubtitleTrack) keys to `playable_item_id` alone.
- `Image`, `Extra`, `ExternalId` use single
  `(owner_type, owner_id)` discriminators with no multi-FK fallback.
- `Library.EntityShape.normalize/3` is deleted from the codebase.
- `Library.WatchedFile.owner_id/1` is deleted from the codebase
  (PlayableItem's id is the answer).
- All Pillar-1 fields are typed: dates as `:date`, durations as
  `:integer` seconds, IDs as `:integer` where they're integers.
- `Library.Person` embedded schema replaces the bare `{:array, :map}`
  shapes on cast/crew.
- Every Library LiveView read path goes through a Pillar 2
  projection (`Library.Views.*`) or has a documented reason it
  doesn't.
- `mix precommit` green; no Credo regressions; all baselines stable
  across three consecutive `scripts/profile` runs.
- ADR-NNN written documenting the PlayableItem reification (it's a
  decision that warrants its own record alongside ADR-029
  data-decoupling).

## Out of scope

- The component-contracts campaign (separate workstream — typed
  LiveView attrs is orthogonal to this schema redesign).
- Acquisition / Downloads / Search context splits (their own
  campaign — desktop-rearchitecture Workstream B).
- The Watcher / KnownFile redesign (separate; out of Library's
  boundary).
- Settings / Capabilities / Controls (already paradigm-correct per
  desktop-rearchitecture).

## Pointers

- [ADR-041 — In-memory projection architecture](../decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md)
- [ADR-029 — Data decoupling](../decisions/architecture/2026-03-26-029-data-decoupling.md)
- [`campaigns/desktop-rearchitecture.md`](desktop-rearchitecture.md) — the projection fan-out partner campaign
- [`docs/library.md`](../docs/library.md) — current schema documentation
- [`lib/media_centarr/library/`](../lib/media_centarr/library/) — current schemas
- [`lib/media_centarr/library/views/continue_watching.ex`](../lib/media_centarr/library/views/continue_watching.ex) — canonical projection example
