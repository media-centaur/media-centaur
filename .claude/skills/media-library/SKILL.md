---
name: media-library
description: "Triggers when user asks about their media library — searching titles, browsing entities, checking watch progress, viewing images, inspecting identifiers, pending review files, or library stats. Activates on movie/show/series names, 'what do I have', 'library stats', 'show me', 'find', 'search'."
---

## Rules

1. **All queries via `mcp__tidewave__project_eval`** — never `execute_sql_query`, never raw SQL
2. **Standard alias block** — paste at the top of every eval:
   ```elixir
   alias MediaCentaur.Repo
   alias MediaCentaur.Library.{Movie, TVSeries, MovieSeries, VideoObject, Season, Episode, Extra, Image, Identifier, WatchedFile, WatchProgress}
   alias MediaCentaur.Review.PendingFile
   import Ecto.Query
   ```
3. **Prefer context functions** — `MediaCentaur.Library.get_tv_series_with_associations/1`, `get_movie_series_with_associations/1`, etc. are already preloaded correctly. Reach for `Repo` directly only when a context function doesn't fit.

## Data Model Quick Reference

The library uses **type-specific tables** — there is NO single `Entity` table. Each media type is its own Ecto schema with its own UUID.

| Schema | Children | Description |
|---|---|---|
| `Movie` | `extras` (and belongs to MovieSeries when `movie_series_id` set) | Standalone movie OR child of a MovieSeries |
| `MovieSeries` | `movies`, `extras` | Film collection (trilogy, anthology) |
| `TVSeries` | `seasons` → `episodes`, `extras` | TV show with seasons and episodes |
| `VideoObject` | — | Standalone video (concert, documentary, single file) |

Any type can have `images`, `identifiers`, and `watched_files`. Each of those join-like schemas has **type-specific FKs**: `movie_id`, `tv_series_id`, `movie_series_id`, `video_object_id` — exactly one is populated per row.

### Key Fields by Schema

| Schema | Key Fields |
|---|---|
| **Movie** | `id`, `name`, `description`, `date_published`, `duration`, `director`, `content_rating`, `content_url`, `url`, `aggregate_rating_value`, `tmdb_id`, `movie_series_id` (nullable — set for collection children), `position` |
| **TVSeries** | `id`, `name`, `description`, `date_published`, `genres`, `number_of_seasons`, `director`, `content_rating`, `aggregate_rating_value` |
| **MovieSeries** | `id`, `name`, `description`, `date_published`, `genres`, `director` |
| **VideoObject** | `id`, `name`, `description`, `date_published`, `duration`, `director`, `content_url`, `url` |
| **Season** | `id`, `season_number`, `number_of_episodes`, `name`, `tv_series_id` |
| **Episode** | `id`, `episode_number`, `name`, `description`, `duration`, `content_url`, `season_id` |
| **Extra** | `id`, `name`, `content_url`, `position`, `movie_id`/`tv_series_id`/`movie_series_id`, `season_id` |
| **Image** | `id`, `role` ("poster"/"backdrop"/"logo"/"thumb"), `url` (remote), `content_url` (local path), `extension`, `movie_id`/`tv_series_id`/`movie_series_id`/`video_object_id`/`episode_id` |
| **Identifier** | `id`, `source` ("tmdb"/"imdb"), `external_id`, `movie_id`/`tv_series_id`/`movie_series_id`/`video_object_id` |
| **WatchedFile** | `id`, `file_path`, `parsed_title`, `parsed_year`, `parsed_type`, `season_number`, `episode_number`, `state`, `watch_dir`, `movie_id`/`tv_series_id`/`movie_series_id`/`video_object_id` |
| **WatchProgress** | `id`, `position_seconds`, `duration_seconds`, `completed`, `last_watched_at`, `movie_id`/`episode_id`/`video_object_id` |
| **PendingFile** | `id`, `file_path`, `parsed_title`, `parsed_year`, `parsed_type`, `tmdb_id`, `confidence`, `match_title`, `status`, `candidates`, `error_message` |

### Pre-built Context Functions

Prefer these over raw `Repo` calls — they load the canonical preloads for each entity type:

| Function | Returns | Preloads |
|---|---|---|
| `Library.get_tv_series_with_associations/1` | `{:ok, %TVSeries{}}` or `{:error, :not_found}` | images, external_ids, extras, watched_files, seasons → (extras, episodes → (images, watch_progress)) |
| `Library.get_movie_series_with_associations/1` | `{:ok, %MovieSeries{}}` or `{:error, :not_found}` | images, external_ids, extras, watched_files, movies → (images, watch_progress) |
| `Library.get_watch_progress_by_fk/2` | `{:ok, %WatchProgress{}}` or `{:error, :not_found}` | — |
| `LibraryBrowser.fetch_all_typed_entries/0` | `[%{entity, progress, progress_records}]` | Everything. Returns all entities wrapped with progress summary. |

## Query Patterns

### Search by name (across all types)

```elixir
alias MediaCentaur.Repo
alias MediaCentaur.Library.{Movie, TVSeries, MovieSeries, VideoObject}
import Ecto.Query

pattern = "%" <> String.downcase("search term") <> "%"

movies = from(m in Movie, where: fragment("lower(?) LIKE ?", m.name, ^pattern)) |> Repo.all()
tv_series = from(t in TVSeries, where: fragment("lower(?) LIKE ?", t.name, ^pattern)) |> Repo.all()
movie_series = from(s in MovieSeries, where: fragment("lower(?) LIKE ?", s.name, ^pattern)) |> Repo.all()
videos = from(v in VideoObject, where: fragment("lower(?) LIKE ?", v.name, ^pattern)) |> Repo.all()

{movies, tv_series, movie_series, videos}
```

SQLite `LIKE` is case-insensitive on ASCII by default; the `lower(...)` wrapper makes it explicit.

### Get a TV series by UUID with full preloads

```elixir
{:ok, tv} = MediaCentaur.Library.get_tv_series_with_associations("uuid-here")
# tv.seasons → [%Season{episodes: [%Episode{images: [...], watch_progress: %WatchProgress{}}]}]
```

### Get a movie series (collection) by UUID

```elixir
{:ok, ms} = MediaCentaur.Library.get_movie_series_with_associations("uuid-here")
# ms.movies → [%Movie{images: [...], watch_progress: %WatchProgress{}}]
```

### Filter by type (all TV series)

```elixir
from(t in TVSeries, order_by: [asc: t.name]) |> Repo.all()
```

### Combined filter (movies with "alien" in the title)

```elixir
pattern = "%alien%"

from(m in Movie,
  where: fragment("lower(?) LIKE ?", m.name, ^pattern) and is_nil(m.movie_series_id),
  order_by: [asc: m.name]
)
|> Repo.all()
```

`is_nil(m.movie_series_id)` filters to STANDALONE movies (not collection children).

### Find by TMDB ID

```elixir
from(i in Identifier,
  where: i.source == "tmdb" and i.external_id == "12345",
  preload: [:movie, :tv_series, :movie_series, :video_object]
)
|> Repo.one()
```

Exactly one of the four belongs_to associations will be non-nil on the result.

### Library statistics

```elixir
%{
  movies: Repo.aggregate(from(m in Movie, where: is_nil(m.movie_series_id)), :count),
  movie_children: Repo.aggregate(from(m in Movie, where: not is_nil(m.movie_series_id)), :count),
  tv_series: Repo.aggregate(TVSeries, :count),
  movie_series: Repo.aggregate(MovieSeries, :count),
  video_objects: Repo.aggregate(VideoObject, :count),
  watched_files: Repo.aggregate(WatchedFile, :count),
  images: Repo.aggregate(Image, :count),
  pending_review: Repo.aggregate(PendingFile, :count)
}
```

### Watch progress for a TV series

```elixir
{:ok, tv} = MediaCentaur.Library.get_tv_series_with_associations("uuid-here")

# Already preloaded through seasons → episodes → watch_progress.
for season <- tv.seasons, episode <- season.episodes, episode.watch_progress do
  {season.season_number, episode.episode_number, episode.watch_progress}
end
```

### Pending review files

```elixir
from(p in PendingFile, where: p.status == :pending, order_by: [asc: p.inserted_at])
|> Repo.all()
```

### Incomplete images (remote URL set, no local download)

```elixir
from(i in Image, where: not is_nil(i.url) and is_nil(i.content_url))
|> Repo.all()
```

### Files linked to a TV series

```elixir
from(w in WatchedFile, where: w.tv_series_id == ^"uuid-here")
|> Repo.all()
```

## Display Guidelines

### Type-specific formatting

**Movie:**
```
**Movie Title** (year)
Rating: X.X | Duration: Xh Xm | Director: Name
Content Rating: PG-13 | Genres: Action, Sci-Fi
TMDB: 12345

Description text here.

Images: poster, backdrop, logo
Files: /path/to/movie.mkv
```

**TV Series:**
```
**Series Title** (year)
Seasons: X | Rating: X.X | Genres: Drama, Comedy
TMDB: 12345

Description text here.

Season 1 (X episodes):
  1. Episode Name
  2. Episode Name
Season 2 (X episodes):
  ...

Images: poster, backdrop
Files: /path/to/episode1.mkv, ...
```

**Movie Series (Collection):**
```
**Collection Title**
Movies: X | TMDB Collection: 8091

1. Movie One (year) - Rating: X.X
2. Movie Two (year) - Rating: X.X

Images: poster, backdrop
```

**Video Object:**
```
**Video Title** (year)
Duration: Xh Xm | Director: Name

Description text here.

Files: /path/to/video.mkv
```

### Watch progress formatting

For TV series — show per-episode progress:
```
Watch Progress:
  S01E03 — 45:30 / 52:00 (87%) — last watched 2026-02-28
  S01E01 — completed
  S01E02 — completed
```

For standalone movies / video objects:
```
Watch Progress: 1:23:45 / 2:01:30 (69%) — last watched 2026-02-28
```

### Section order

1. Title line with year
2. Key metadata (rating, duration, genres, director)
3. External IDs (TMDB, IMDB)
4. Description
5. Children (seasons/episodes or collection movies)
6. Extras (if any)
7. Images (list roles that exist)
8. Watch progress (if any)
9. Linked files

## Workflow: "Show Me Everything About X"

1. **Search across all four types** using the pattern at the top of Query Patterns.
2. **Handle results:**
   - 0 results → try broader search, suggest checking pending review files
   - 1 result → proceed to display
   - Multiple → list matches with type badges, ask user which one
3. **Load fully:** reach for the appropriate `Library.get_*_with_associations/1` function based on type, or use the preload shape from the function for direct `Repo.get/2` calls.
4. **Extract identifiers:** the Identifier schema has a `source` field (`"tmdb"`/`"imdb"`) and an `external_id` field. TMDB ID = `Enum.find(entity.identifiers, &(&1.source == "tmdb")).external_id`.
5. **Display** using the type-specific template above.
6. **Offer follow-ups:**
   - "Want to see the full episode list?"
   - "Want to check watch progress?"
   - "Want to see image details?"
   - "Want to see the raw data?"

## Suggesting improvements

When you hit friction while querying the library, suggest improvements:

### Skill improvements
Missing query patterns, awkward examples, bad formatting — propose adding to this skill. Examples: search by genre, date-range filters, better display for edge cases.

### Context function improvements
If a raw `Repo.all` pattern keeps coming up, suggest adding a named function to `MediaCentaur.Library`. Examples:
- `search_all_types/1` — cross-type name search with a unified result shape
- `count_by_type/0` — library statistics as a single call
- `find_by_tmdb_id/1` — single-call TMDB lookup across all four types

Frame as "consider adding" suggestions — the user decides.
