# Data Format

Reference for the entity data shape used by the LiveView UI and by the
library context's public functions.

The **canonical source of truth is the Ecto schema modules** in
`lib/media_centarr/library/`. Each schema's `@type` and field
declarations define the on-disk and in-memory structure. This document
exists to describe how those schemas combine into the entry shape the UI
consumes — it does not duplicate per-field definitions.

---

## Entity Types

Each playable type is its own schema and its own table:

| Type | Module | Table | Children |
|------|--------|-------|----------|
| Movie (standalone or in a series) | `MediaCentarr.Library.Movie` | `library_movies` | Extras |
| TV Series | `MediaCentarr.Library.TVSeries` | `library_tv_series` | Seasons → Episodes; Extras |
| Movie Series | `MediaCentarr.Library.MovieSeries` | `library_movie_series` | Movies; Extras |
| Video Object | `MediaCentarr.Library.VideoObject` | `library_video_objects` | — |

Embedded under those: `Season`, `Episode`, `Extra`, `ExternalId`,
`Image`, `WatchedFile`, `WatchProgress`. Each one is a regular Ecto
schema; read the module to see its fields.

### Common identity

Every type record has:

- a UUID primary key (the `id` field), assigned at creation and never
  changed — see [ADR-005](../decisions/architecture/2026-02-20-005-entity-identity-and-image-storage.md)
- snake_case field names that match the Ecto schema declaration
  (`name`, `description`, `date_published`, `content_url`, `genres`,
  `duration`, `director`, `content_rating`, `aggregate_rating_value`,
  `url`)

Entity records are passed around as Ecto structs. The LiveView UI reads
struct fields directly; there is no JSON serialization in the entity
data path.

---

## Library Entry Shape

`Library.Browser.list_entries/0` and the related browser functions
return entries in this shape:

```elixir
%{
  entity: %Library.Movie{...} | %Library.TVSeries{...} | ...,
  progress: ProgressSummary.t() | nil,
  progress_records: [WatchProgress.t()],
  resume_target: ResumeTarget.t() | nil,
  child_targets: %{String.t() => ResumeTarget.t()} | nil,
  last_activity_at: DateTime.t() | nil
}
```

- `entity` — an Ecto struct of one of the four playable types, with
  associations preloaded as documented in `Library.full_preloads_by_type/0`
- `progress` — aggregate summary returned by
  `Library.ProgressSummary.compute/2` (e.g. episodes completed / total)
- `progress_records` — the underlying per-child `WatchProgress` rows
- `resume_target` — a hint for what plays when the user hits "play";
  see `MediaCentarr.Playback.ResumeTarget`
- `child_targets` — per-child resume hints, keyed by the child UUID
  (used for season/episode navigation in TV series; `nil` for
  single-item entities)
- `last_activity_at` — newest of `inserted_at` and the most recent watch
  event across the entity and its children; the Continue Watching list
  is sorted by this

---

## See Also

- [`IMAGE-CACHING.md`](IMAGE-CACHING.md) — image roles, directory
  layout, HTTP serving
- [`docs/library.md`](../docs/library.md) — broader explanation of the
  Library context
- The schema modules themselves (`lib/media_centarr/library/*.ex`) —
  authoritative for fields and types
