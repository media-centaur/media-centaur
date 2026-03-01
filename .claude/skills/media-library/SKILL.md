---
name: media-library
description: "Triggers when user asks about their media library — searching titles, browsing entities, checking watch progress, viewing images, inspecting identifiers, pending review files, or library stats. Activates on movie/show/series names, 'what do I have', 'library stats', 'show me', 'find', 'search'."
---

## Rules

1. **All queries via `project_eval`** — never `execute_sql_query`, `Ecto.Query`, or `Repo`
2. **Always `require Ash.Query`** in eval blocks — `filter` is a macro
3. **Standard alias block** — paste at the top of every eval:
   ```elixir
   alias MediaCentaur.Library.{Entity, Image, Identifier, Movie, Season, Episode, Extra, WatchedFile, WatchProgress}
   alias MediaCentaur.Review.PendingFile
   require Ash.Query
   ```

## Data Model Quick Reference

### Entity Types and Their Children

| Entity Type | Children | Description |
|---|---|---|
| `:movie` | — | Standalone movie |
| `:movie_series` | `movies` | Film collection (e.g. trilogy) |
| `:tv_series` | `seasons` → `episodes` | TV show |
| `:video_object` | — | Standalone video (concert, documentary) |

Any entity type can have `extras` (bonus features) and `images`.

### Key Fields by Resource

| Resource | Key Fields |
|---|---|
| **Entity** | `id`, `type`, `name`, `description`, `date_published`, `genres`, `content_url`, `url`, `duration`, `director`, `content_rating`, `number_of_seasons`, `aggregate_rating_value` |
| **Movie** | `id`, `name`, `description`, `date_published`, `duration`, `director`, `content_rating`, `content_url`, `url`, `aggregate_rating_value`, `tmdb_id`, `position`, `entity_id` |
| **Season** | `id`, `season_number`, `number_of_episodes`, `name`, `entity_id` |
| **Episode** | `id`, `episode_number`, `name`, `description`, `duration`, `content_url`, `season_id` |
| **Extra** | `id`, `name`, `content_url`, `position`, `entity_id`, `season_id` |
| **Image** | `id`, `role` ("poster"/"backdrop"/"logo"/"thumb"), `url` (remote), `content_url` (local path), `extension`, `entity_id`/`movie_id`/`episode_id` |
| **Identifier** | `id`, `property_id` ("tmdb"/"tmdb_collection"/"imdb"), `value`, `entity_id` |
| **WatchedFile** | `id`, `file_path`, `state` (:complete), `watch_dir`, `entity_id` |
| **WatchProgress** | `id`, `season_number`, `episode_number`, `position_seconds`, `duration_seconds`, `completed`, `last_watched_at`, `entity_id` |
| **PendingFile** | `id`, `file_path`, `parsed_title`, `parsed_year`, `parsed_type`, `tmdb_id`, `confidence`, `match_title`, `status` (:pending/:approved/:dismissed), `candidates`, `error_message` |

### Pre-Built Read Actions

| Resource | Action | What It Does |
|---|---|---|
| Entity | `:with_associations` | Loads images, identifiers, watch_progress, extras, seasons (with extras + episodes with images), movies (with images). **Does NOT load `watched_files`** — chain `Ash.load!` if needed. |
| Entity | `:with_progress` | Loads watch_progress, seasons (with episodes), movies |
| Entity | `:with_images` | Loads images, seasons (with episodes+images), movies (with images) |
| Identifier | `:find_by_tmdb_id` | Arg: `tmdb_id` (string). Filters `property_id == "tmdb"`, loads `:entity`, limit 1 |
| Identifier | `:find_by_tmdb_collection` | Arg: `collection_id` (string). Filters `property_id == "tmdb_collection"`, loads `:entity`, limit 1 |
| Image | `:incomplete` | Filters images with `url` set but no `content_url` (not yet downloaded). Loads `:entity` |
| WatchProgress | `:for_entity` | Arg: `entity_id`. Sorted by season_number, episode_number ascending |
| PendingFile | `:pending` | Filters `status == :pending`, sorted by `inserted_at` ascending |

## Query Patterns

### Search by Name

```elixir
alias MediaCentaur.Library.Entity
require Ash.Query

Entity
|> Ash.Query.filter(contains(name, "search term"))
|> Ash.read!(action: :with_associations)
```

`contains/2` is case-insensitive on SQLite.

### Get Entity by ID

```elixir
entity = Ash.get!(Entity, "uuid-here", action: :with_associations)
# To also load watched_files (not included in :with_associations):
entity = Ash.load!(entity, [:watched_files])
```

### Filter by Type

```elixir
Entity
|> Ash.Query.filter(type == :tv_series)
|> Ash.read!(action: :with_associations)
```

### Combined Filters

```elixir
Entity
|> Ash.Query.filter(type == :movie and contains(name, "alien"))
|> Ash.read!(action: :with_associations)
```

### Sort Results

```elixir
Entity
|> Ash.Query.sort(name: :asc)
|> Ash.read!()
```

### Find by TMDB ID

```elixir
alias MediaCentaur.Library.Identifier
require Ash.Query

# Returns list — take first element
[identifier] = Identifier |> Ash.Query.for_read(:find_by_tmdb_id, %{tmdb_id: "12345"}) |> Ash.read!()
entity = identifier.entity
```

### Find by TMDB Collection ID

```elixir
[identifier] = Identifier |> Ash.Query.for_read(:find_by_tmdb_collection, %{collection_id: "8091"}) |> Ash.read!()
entity = identifier.entity
```

### List All Entities (Names + Types)

```elixir
Entity
|> Ash.Query.sort(name: :asc)
|> Ash.read!()
|> Enum.map(fn e -> "#{e.name} (#{e.type})" end)
```

### Library Statistics

```elixir
alias MediaCentaur.Library.{Entity, WatchedFile, Image}
require Ash.Query

total = Ash.count!(Entity)
movies = Entity |> Ash.Query.filter(type == :movie) |> Ash.count!()
tv = Entity |> Ash.Query.filter(type == :tv_series) |> Ash.count!()
collections = Entity |> Ash.Query.filter(type == :movie_series) |> Ash.count!()
videos = Entity |> Ash.Query.filter(type == :video_object) |> Ash.count!()
files = Ash.count!(WatchedFile)
images = Ash.count!(Image)

"#{total} entities (#{movies} movies, #{tv} TV series, #{collections} collections, #{videos} videos), #{files} files, #{images} images"
```

### Watch Progress for an Entity

```elixir
alias MediaCentaur.Library.WatchProgress
require Ash.Query

WatchProgress
|> Ash.Query.for_read(:for_entity, %{entity_id: "uuid-here"})
|> Ash.read!()
```

### Pending Review Files

```elixir
alias MediaCentaur.Review.PendingFile
require Ash.Query

PendingFile
|> Ash.Query.for_read(:pending)
|> Ash.read!()
```

### Incomplete Images (Missing Downloads)

```elixir
alias MediaCentaur.Library.Image
require Ash.Query

Image
|> Ash.Query.for_read(:incomplete)
|> Ash.read!()
```

### Files Linked to an Entity

```elixir
entity = Ash.get!(Entity, "uuid-here")
entity = Ash.load!(entity, [:watched_files])
entity.watched_files
```

## Display Guidelines

### Type-Specific Formatting

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

### Watch Progress Formatting

```
Watch Progress:
  S01E03 - 45:30 / 52:00 (87%) — last watched 2026-02-28
  S01E01 - completed
  S01E02 - completed
```

For movies/videos (season_number=0, episode_number=0):
```
Watch Progress: 1:23:45 / 2:01:30 (69%) — last watched 2026-02-28
```

### Section Order

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

1. **Search:** `Ash.Query.filter(contains(name, "search term"))` with `:with_associations`
2. **Handle results:**
   - 0 results → try broader search, suggest checking pending review files
   - 1 result → proceed to display
   - Multiple → list matches with types, ask user which one
3. **Load fully:**
   ```elixir
   entity = Ash.load!(entity, [:watched_files])
   ```
4. **Extract identifiers:** find TMDB ID from `entity.identifiers` where `property_id == "tmdb"`
5. **Display** using the type-specific template above
6. **Offer follow-ups:**
   - "Want to see the full episode list?"
   - "Want to check watch progress?"
   - "Want to see image details?"
   - "Want to see the raw data?"

## Suggesting Improvements

When you encounter friction while querying the library, suggest improvements:

### Skill Improvements
If a query pattern is missing, awkward, or could be better formatted — suggest adding it to this skill. Examples:
- New display templates for edge cases
- Additional search patterns (by genre, by year range, etc.)
- Better formatting for specific data shapes

### Ash Resource Improvements
If a query would be easier with a new read action, relationship, or attribute — suggest adding it. Examples:
- Entity lacks a `:search_by_name` read action — currently done inline with `Ash.Query.filter(contains(name, ...))`
- `:with_associations` doesn't load `watched_files` — could be added to the prepare block
- Any query pattern the user repeats should become a named read action

Frame these as "consider adding" suggestions — the user decides whether it's worth the change.
