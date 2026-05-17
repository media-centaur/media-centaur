---
status: accepted
date: 2026-05-17
---
# PlayableItem is the canonical leaf of the Library schema

## Context and Problem Statement

The Library bounded context represents user media in four shapes —
standalone movies, series-child movies, TV episodes, and standalone
video objects — backed by four type-specific container tables. Before
Schema v2 the supporting tables (`WatchedFile`, `WatchProgress`,
`Image`, `Extra`, `ExternalId`, subtitle metadata) each carried 3–5
nullable foreign keys, one per container type, with the invariant
"exactly one is non-null" enforced only in application code.

The fanout came with concrete failures:

1. **No "exactly one" enforcement.** SQLite has no native
   discriminated-union; the "exactly one FK set" invariant lived in
   ad-hoc helpers like `WatchedFile.owner_id/1` and `EntityShape.normalize/3`,
   each accreted as a new container type was added. Regressions
   surfaced as orphan rows or nil pointer crashes at the render layer.
2. **Multiple sources of truth for the same fact.** `tmdb_id` lived on
   every container *and* on `ExternalId`. `content_url` lived on
   `Movie`/`Episode`/etc *and* on `WatchedFile`. `duration` lived as a
   string ISO 8601 on containers and as a parsed integer at the
   render layer. Drift between copies was a recurring bug class.
3. **Real concepts were unrepresentable.** A theatrical cut + a
   director's cut of the same movie are two playable units belonging
   to one movie — the pre-v2 schema had no row to put them on. Same
   for two-part episodes. The codebase routed around this with
   special-cases at the read layer rather than fixing the model.
4. **The pipeline carried polymorphism debt.** Every projection,
   broadcast coalescer, and cache had to know about all four
   container shapes; adding a fifth (audiobooks, music) compounded
   the surface area linearly.

## Decision Outcome

Chosen option: **reify the user-visible playable unit as a first-class
schema, `Library.PlayableItem`, and reshape every supporting table
around it.**

The user-visible playable unit is "press play and watch": a thing
with a file, a duration, and watch progress. Movie, episode,
movie-series-child, and video-object are four ways the same concept
manifests in the UI; they are not four data shapes.

The reified leaf:

```elixir
schema "library_playable_items" do
  field :container_type, Ecto.Enum, values: [:movie, :episode, :video_object]
  field :container_id, Ecto.UUID
  field :position, :integer          # episode number / series order / 1 for solo
  field :duration_seconds, :integer  # canonical, integer
  field :name, :string               # override label ("Director's Cut")

  has_many :watched_files, Library.WatchedFile
  has_one  :watch_progress, Library.WatchProgress
  has_many :subtitle_tracks, Library.SubtitleTrack
  has_many :images, Library.Image, where: [owner_type: :playable_item]

  timestamps()
end
```

Concretely the schema reshapes as follows:

| Table | Pre-v2 | Schema v2 |
|-------|--------|-----------|
| `WatchedFile`     | 4 nullable FKs (movie/episode/movie_series_child/video_object) | single `playable_item_id` |
| `WatchProgress`   | 4 nullable FKs, `(season=0, episode=0)` overload | single `playable_item_id` |
| `SubtitleTrack`   | inline `{:array, :map}` on `WatchedFile` | own table, `watched_file_id` |
| `Image`           | 4 nullable FKs | `(owner_type, owner_id)` single discriminator |
| `Extra`           | 4 nullable FKs | `(owner_type, owner_id)` single discriminator |
| `ExternalId`      | duplicated on each container | sole source of truth |
| `Movie` / `Episode` / etc | held `content_url`, `tmdb_id`, `imdb_id`, parsed-on-read strings | metadata only; identifiers in `ExternalId`, content via `PlayableItem` → `WatchedFile` |

Pillar-1 fields are typed end-to-end: `date_published :date` (not
string), `duration_seconds :integer` (not ISO 8601 string), `cast` /
`crew` as `embeds_many` of the `Library.Person` schema (not free maps).
The `EntityShape.normalize/3` helper that smoothed over the
pre-v2 shape inconsistencies is retired.

### Consequences

* **Good** — supporting tables collapse from 3–5-FK fanout to a single
  FK (or a single discriminator), and the "exactly one is non-null"
  invariant is replaced by a structurally-enforced "exactly one
  `playable_item_id`".
* **Good** — multi-cut movies and multi-part episodes are natural data
  shapes: N `PlayableItem` rows pointing at the same container. No
  read-layer special cases.
* **Good** — one source of truth for `tmdb_id` (`ExternalId`),
  `content_url` (`WatchedFile`), and `duration` (`PlayableItem.duration_seconds`).
  Cross-cut drift bugs eliminated structurally.
* **Good** — typed fields throughout remove parse-on-every-read
  overhead and let the projection layer ship sort/filter/compare
  primitives without coercion.
* **Good** — projections become uniformly leaf-keyed: every Library
  view rebuild fans out from `playable_item_id`, so adding a new
  projection is one query plus one ETS table rather than a four-way
  union over container types.
* **Bad** — lost SQLite FK enforcement on the three polymorphic
  tables (`Image`, `Extra`, `ExternalId`). App-level integrity via
  `Library.Inbound` and context functions replaces it. Acceptable
  because (a) writes already funnel through those entry points and
  (b) the pre-v2 schema had no DB-level "exactly one FK" constraint
  either, so we're not losing a guarantee we had.
* **Bad** — required a full Pillar-1 rewrite spanning three phases and
  several sessions, plus a downstream projection cutover (Phase 3).
  Schema rewrites are normally expensive; this one was tractable
  because pre-public status removed the migration-compatibility
  constraint.

## Pointers

* Full implementation record:
  [`campaigns/done/library-schema-v2.md`](../../campaigns/done/library-schema-v2.md).
  The campaign carries the per-phase task lists, schema diagrams, and
  closure-pass deferral list.
* Related decisions:
  * [ADR-029](2026-03-26-029-data-decoupling.md) — Library boundary as
    the single write entry point; this ADR rests on that constraint.
  * [ADR-041](2026-05-10-041-in-memory-projection-architecture.md) —
    in-memory projections; the v2 schema is the Pillar-1 shape those
    projections rebuild from.
  * [ADR-045](2026-05-17-045-file-presence-ownership.md) — file
    presence ownership; uses `PlayableItem` as the leaf the presence
    cascade ultimately reaches.
