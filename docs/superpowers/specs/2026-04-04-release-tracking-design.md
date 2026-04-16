# New Release Tracking — Design Spec

## Context

Media Centarr's library manages media you already own. There's no way to track upcoming releases — new seasons of TV shows you're watching, or sequels in movie series you follow. This feature adds a new "Release Tracking" bounded context that monitors TMDB for upcoming content related to your library, with a dedicated UI zone in the library view.

The feature is fully isolated from the Library context's database. It maintains its own tables, images, and TMDB extraction logic. The data model is designed to support a future "manual search and track" feature for items not in your library.

---

## Data Model

### Context: `MediaCentarr.ReleaseTracking`

Table prefix: `release_tracking_`

### Table: `release_tracking_items`

Represents a movie or TV series being tracked.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | PK |
| `tmdb_id` | integer | not null |
| `media_type` | enum `:movie` / `:tv_series` | not null |
| `name` | string | cached from TMDB |
| `status` | enum `:watching` / `:ignored` | default `:watching` |
| `source` | enum `:library` / `:manual` | how it was added |
| `library_entity_id` | UUID, nullable | loose reference to library entity (not a real FK) |
| `last_refreshed_at` | utc_datetime | last successful TMDB query |
| `poster_path` | string, nullable | local relative path to downloaded poster |

Unique constraint on `{tmdb_id, media_type}`.

### Table: `release_tracking_releases`

Individual upcoming release events — one row per episode or movie.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | PK |
| `item_id` | UUID FK → items | not null |
| `air_date` | date, nullable | null = "release date unknown" |
| `title` | string, nullable | episode title if known |
| `season_number` | integer, nullable | for TV |
| `episode_number` | integer, nullable | for TV |
| `released` | boolean | default false, flipped when date passes |

### Table: `release_tracking_events`

Change log — notable changes detected during TMDB refresh.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | PK |
| `item_id` | UUID FK → items | not null |
| `event_type` | enum | see below |
| `description` | string | human-readable summary |
| `metadata` | map/json | structured data (old_date, new_date, etc.) |
| `inserted_at` | utc_datetime | when detected |

Event types: `:date_changed`, `:new_season_announced`, `:new_episodes_announced`, `:item_added`, `:item_cancelled`

---

## Backend Architecture

### Module Structure

```
lib/media_centarr/release_tracking/
  item.ex              # Ecto schema
  release.ex           # Ecto schema
  event.ex             # Ecto schema
  extractor.ex         # Pure functions: TMDB JSON → structured release data
  differ.ex            # Pure functions: old releases × new releases → change events
  scanner.ex           # Scans library external IDs, queries TMDB, creates tracking items
  refresher.ex         # GenServer: periodic TMDB refresh cycle
  image_store.ex       # Downloads/manages poster images

lib/media_centarr/release_tracking.ex  # Context facade
```

### Context Facade: `MediaCentarr.ReleaseTracking`

Public API:
- `list_watching_items/0` — items with status `:watching`
- `list_releases/1` — upcoming and recently released, grouped for UI
- `list_recent_events/1` — change log
- `track_item/1` — add a new tracked item
- `ignore_item/1` / `watch_item/1` — toggle status
- `tracking_status/1` — given `{tmdb_id, media_type}`, returns `:watching` / `:ignored` / `nil`

### Extractor: `ReleaseTracking.Extractor`

Pure function module. Takes raw TMDB JSON, returns structured data:
- `extract_tv_releases(tv_response)` → list of `%{air_date, season_number, episode_number, title}`
  - Reads `next_episode_to_air`, `status`, season episode air dates
- `extract_tv_status(tv_response)` → `:returning` / `:ended` / `:canceled` / `:in_production`
  - Maps TMDB `status` string values
- `extract_collection_releases(collection_response)` → list of `%{air_date, title, tmdb_id}`
  - Checks `parts` for unreleased entries
- `extract_movie_status(movie_response)` → `:released` / `:in_production` / `:planned` / etc.

Available TMDB fields (present in responses but not used by existing Mapper):
- TV: `status`, `next_episode_to_air` (object: air_date, episode_number, season_number, name), `last_episode_to_air`
- Movie: `status` ("Rumored"/"Planned"/"In Production"/"Post Production"/"Released"/"Canceled")
- Season episodes: `air_date` per episode
- Collection parts: full movie objects with `release_date`

### Differ: `ReleaseTracking.Differ`

Pure function module. Compares stored releases against freshly extracted releases:
- `diff(old_releases, new_releases)` → list of event structs
- Detects: date changes, new episodes, new seasons, cancellations, removed releases

### Scanner: `ReleaseTracking.Scanner`

Triggered by UI scan button. Uses `Task.Supervisor` for parallelism:
1. Queries `library_external_ids` where `source = "tmdb"` (acceptable cross-context read)
2. For each TMDB ID: fetches via `TMDB.Client`, runs through `Extractor`
3. TV series: tracks if `status` is "Returning Series" or "In Production" or has future air dates
4. Movies in collections: tracks collection if any part has future `release_date` or non-"Released" status
5. Standalone released movies: skipped
6. Creates tracking items + releases, writes `:item_added` events
7. Idempotent — skips already-tracked items
8. Respects `TMDB.RateLimiter`

### Refresher: `ReleaseTracking.Refresher`

GenServer with `Process.send_after` (default 24h, configurable):
- On tick: iterates all `:watching` items
- Fetches fresh TMDB data per item
- Runs `Extractor` → `Differ` against stored releases
- Writes change events to `release_tracking_events`
- Upserts `release_tracking_releases` with current data
- Flips `released: true` for any release with `air_date <= today`
- Downloads/updates poster via `ImageStore` if changed
- Auto-stops tracking for ended/canceled shows with no future dates
- Broadcasts `{:releases_updated, item_ids}` to `"release_tracking:updates"`

### Image Storage

- Path: `data/images/tracking/{tmdb_id}/poster.jpg`
- Own directory, fully independent from library images
- Poster only (lightweight)
- `ReleaseTracking.ImageStore` handles download via existing image download infrastructure

### PubSub

New topic added to `Topics` module:
- `"release_tracking:updates"` — broadcasts when releases change

### Supervision

Added to `Application.start/2`:
- `ReleaseTracking.Refresher` (GenServer)
- Scanner runs on-demand via `Task.Supervisor` (not a permanent process)

---

## UI Integration

### Zone Tab

Third tab in the library tablist:

```
[ Continue Watching ] [ Library ] [ Upcoming ]
```

URL: `/?zone=upcoming`. `parse_zone/1` adds `:upcoming`. Follows existing `push_patch` pattern.

### Upcoming Zone Layout (top to bottom)

**1. Released Section** (conditional — only if recently released items exist)
- Header: "Released"
- List of items released in the last ~30 days
- Each row: poster thumbnail, name, release date, type indicator

**2. Summary Cards**
- **Movies**: one line per tracked movie — name + release date or "Release date unknown"
- **TV Series**: one line per tracked series — name + next episode info ("Season 3 Episode 1 — Mar 3, 2026") or "No date announced"
- Compact text, no posters — at-a-glance overview

**3. Chronological Release List**
- Grouped by date ascending
- Date headers: "March 3, 2026"
- Under each date: items with context
  - TV: `Show Name: Season 3 Episode 1 — "Episode Title"`
  - Movie: `Movie Name`
- "Release date unknown" items grouped at bottom under own header

**4. Scan Button**
- Toolbar area (same position as sort/filter in Library zone)
- Triggers scanner, shows loading state

**5. Recent Changes** (from events table)
- Small section at bottom or toggle
- Shows notable events: "Release date moved from Apr 15 to Jun 3", "New season announced"

### Detail Page Watch Icon

On the entity detail panel (modal opened from library grid):
- Small icon top-right of backdrop area
- States: watching (filled), ignored (crossed out), not tracked (dimmed/absent)
- Click toggles watching ↔ ignored
- Only visible for entities with a TMDB external ID
- LiveView queries `ReleaseTracking.tracking_status/1`

### Data Flow

- `library_live.ex` subscribes to `"release_tracking:updates"` when zone is `:upcoming`
- Upcoming zone data fetched via `ReleaseTracking` facade on mount/handle_params
- No streams needed — release list is small enough for direct assigns
- Detail page icon: loaded alongside entity data, cached in assigns

---

## TMDB Data Strategy

### What triggers tracking

| Library Entity | TMDB Check | Track If |
|----------------|------------|----------|
| TV Series | `get_tv(tmdb_id)` → read `status`, `next_episode_to_air` | Status is "Returning Series" or "In Production", or has future air dates |
| Movie in MovieSeries | `get_collection(collection_id)` → read `parts` | Any part has future `release_date` or non-"Released" status |
| Standalone Movie | — | Skipped (already released if in library) |

### What triggers "released"

Daily in Refresher tick: any release with `air_date <= today` and `released == false` → flip to `released: true`.

### When tracking auto-stops

- TV: `status` is "Ended" or "Canceled" AND no future air dates remain
- Movies: all collection parts have `status` "Released" and release dates passed
- Writes final event, item ages out of Released section naturally

---

## Testing Strategy

### Pure Function Tests (async: true, no DB)

**Extractor:**
- `extract_tv_releases/1` — returning series, ended, no next episode, future episodes, missing fields
- `extract_tv_status/1` — each TMDB status string
- `extract_collection_releases/1` — mix of released and unreleased parts
- `extract_movie_status/1` — each status string
- Edge cases: null `air_date`, null `next_episode_to_air`, missing keys

**Differ:**
- Date changed detection
- New episodes/seasons appearing
- Releases disappearing
- No changes (idempotent)

### Resource Tests (DataCase, real DB)

**Schemas:** valid creation, required fields, unique constraints, status transitions
**Facade:** `track_item`, `ignore_item`, `watch_item`, `list_watching_items`, `list_releases`, `tracking_status`

### Scanner Tests (TMDB stubs via Req.Test)

- Correct items/releases created from stubbed responses
- Idempotent (no duplicates on re-scan)
- Skips already-tracked and ended/canceled

### Refresher Tests

- Diff events generated on date change, new episodes, cancellation
- Released flag flipped correctly

### Factory Additions

`build_tracking_item/1`, `build_tracking_release/1`, `create_tracking_item/1`, `create_tracking_release/1`

---

## Future: Manual TMDB Search

Not built now, but the data model supports it. A future feature would add a search UI that calls `TMDB.Client.search_movie/search_tv`, lets the user pick a result, and creates a tracking item with `source: :manual` and no `library_entity_id`. The Refresher already handles all items uniformly regardless of source.
