# Data Format

Reference for the entity data shape used by the LiveView UI and by the
library context's public functions.

The **canonical source of truth is the Ecto schema modules** in
`lib/media_centaur/library/`. Each schema's `@type` and field
declarations define the on-disk and in-memory structure. This document
exists to describe how those schemas combine into the entry shape the UI
consumes — it does not duplicate per-field definitions.

---

## Entity Types

Each playable type is its own schema and its own table:

| Type | Module | Table | Children |
|------|--------|-------|----------|
| Movie (standalone or in a series) | `MediaCentaur.Library.Movie` | `library_movies` | Extras |
| TV Series | `MediaCentaur.Library.TVSeries` | `library_tv_series` | Seasons → Episodes; Extras |
| Movie Series | `MediaCentaur.Library.MovieSeries` | `library_movie_series` | Movies; Extras |
| Video Object | `MediaCentaur.Library.VideoObject` | `library_video_objects` | — |

Embedded under those: `Season`, `Episode`, `Extra`, `ExternalId`,
`Image`, `WatchedFile`, `WatchProgress`. Each one is a regular Ecto
schema; read the module to see its fields.

### Common identity

Every type record has:

- a UUID primary key (the `id` field), assigned at creation and never
  changed (see *Entity* in [`docs/GLOSSARY.md`](../docs/GLOSSARY.md))
- snake_case field names that match the Ecto schema declaration
  (`name`, `description`, `date_published`, `content_url`, `genres`,
  `duration`, `director`, `content_rating`, `aggregate_rating_value`,
  `url`)

Entity records are passed around as Ecto structs. The LiveView UI reads
struct fields directly; there is no JSON serialization in the entity
data path.

---

## Library Entry Shape

`Library.Browser.fetch_all_typed_entries/1` (the database path) returns entries in this shape; the Browse projection (`Library.Views.Browse`, ADR-041) carries the same data as `Views.BrowseItem` structs, and the struct is the authority for field names:

```elixir
%{
  entity: %Library.Movie{...} | %Library.TVSeries{...} | ...
}
```

- `entity` — an Ecto struct of one of the four playable types, with
  associations preloaded as documented in `Library.Containers.full_preloads_by_type/0`

An entry carries no watch state. Progress is one profile's and is read
beside the entries: `Library.ProgressRecords.title_progresses/2` returns
`%{entity_id => Library.TitleProgress.t()}` for the ids on screen — the
state, the next item and the measure a card's bar shows — and
`Library.ProgressRecords.last_watched_at_by_title/2` the time the
Recently Watched order sorts by. A title absent from the first map is
unstarted. See the `MediaCentaur.Library.TitleProgress` moduledoc.

---

## See Also

- [`IMAGE-CACHING.md`](IMAGE-CACHING.md) — image roles, directory
  layout, HTTP serving
- [`docs/library.md`](../docs/library.md) — broader explanation of the
  Library context
- The schema modules themselves (`lib/media_centaur/library/*.ex`) —
  authoritative for fields and types
