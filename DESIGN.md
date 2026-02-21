# Media Manager — Application Design

> **Status:** Active (in development)
> **Last updated:** 2026-02-21

This document captures the full architecture of the `media-manager` Phoenix/Elixir application before implementation begins. Format contracts (`media.json`, images) are specified in `../specifications/`; this document covers app-internal design.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Configuration](#2-configuration)
3. [Mount Resilience](#3-mount-resilience)
4. [Pipeline Architecture](#4-pipeline-architecture)
5. [File Name Parsing](#5-file-name-parsing)
6. [Ash Resources (SQLite)](#6-ash-resources-sqlite)
7. [TMDB API Usage](#7-tmdb-api-usage)
8. [media.json Write Strategy](#8-mediajson-write-strategy)
9. [Web UI (Admin Panel)](#9-web-ui-admin-panel)
10. [Dependencies](#10-dependencies)
11. [Open Questions / Future Work](#11-open-questions--future-work)

---

## 1. Overview

The media manager is the **write-side** of Freedia Center. It watches a configured `media_dir` for newly completed torrent downloads, identifies the content, scrapes metadata and artwork from external APIs, and maintains `media.json` (at `shared_media_library`) and the image cache (at `media_images_dir`) that the `user-interface` reads.

**SQLite is the canonical database.** All entity data (names, descriptions, genres, TMDB IDs, image remote URLs, season/episode structure) is stored in SQLite. `media.json` is a generated export of SQLite data — it can always be regenerated. This means:

- Moving output paths → update config, regenerate, done
- Output paths become unavailable → app continues, writes queue, resume on reconnect
- `media.json` corrupted or deleted → regenerate from SQLite instantly
- Images lost → remote `url` stored in SQLite → re-download on demand

**Media types supported:** Movies, TVSeries (full episode metadata), VideoObject (fallback for unidentified content).

**Out of scope:** Games, subtitle management.

---

## 2. Configuration

**File:** `~/.config/freedia-center/media-manager.toml`

At startup, `MediaManager.Config` (a GenServer) reads this file and merges it over compiled defaults from `config/runtime.exs`. Values are accessible via `MediaManager.Config.get(:key)`.

```toml
# ~/.config/freedia-center/media-manager.toml

# Directory containing video/media files (e.g. torrent downloads folder).
# Watched for additions and removals. May be on a removable or network drive.
media_dir = "/mnt/videos/Videos"

# Path to the media library JSON file, read by the user-interface.
# Must match the path the user-interface is configured to read from.
shared_media_library = "~/.local/share/freedia-center/media.json"

# Directory for cached artwork images, one subdirectory per entity UUID.
# Must match the path the user-interface is configured to read from.
media_images_dir = "~/.local/share/freedia-center/images"

[tmdb]
api_key = ""

[pipeline]
# Confidence score threshold (0.0–1.0). Matches at or above this score are
# written automatically. Below it, the item is queued for human review.
auto_approve_threshold = 0.85
```

**Defaults (`config/runtime.exs`):**

```elixir
config :media_manager,
  media_dir: System.get_env("MEDIA_DIR", "/mnt/videos/Videos"),
  shared_media_library: System.get_env("SHARED_MEDIA_LIBRARY", "~/.local/share/freedia-center/media.json"),
  media_images_dir: System.get_env("MEDIA_IMAGES_DIR", "~/.local/share/freedia-center/images"),
  tmdb_api_key: System.get_env("TMDB_API_KEY", ""),
  auto_approve_threshold: 0.85
```

**TOML parsing:** `toml_elixir` library (added to `mix.exs`).

**SQLite database location:** `~/.local/share/freedia-center/media-manager.db` (XDG data home, on system drive — separate from the shared media paths, so it survives any mount failure).

---

## 3. Mount Resilience

Both `media_dir` and the shared output paths (`shared_media_library`, `media_images_dir`) may reside on removable drives, NAS shares, or external mounts. The application must never lose library data due to a transient mount failure.

### 3.1 `media_dir` Resilience (file watcher)

**Core invariant:** A removal event is only valid when `media_dir` is confirmed mounted and accessible. Never remove a library entry solely on the basis of a raw deletion event.

**Three layers of defence:**

1. **Gate every removal on mount health.** Before `RemovalHandler` processes any `:deleted` event, check that `media_dir` is still accessible (`File.stat/1`). If it fails → suppress the removal, emit a warning.

2. **Handle inotify unmount events explicitly.** On Linux, inotify fires `IN_UNMOUNT` when a watched filesystem is ejected. `:file_system` surfaces this as `[:unmounted]`. The `Watcher` transitions to `:media_dir_unavailable` state and stops forwarding any events downstream.

3. **Suspicious burst detection.** If ≥50 removal events fire within 2 seconds and `media_dir` appears accessible, pause processing and alert in the admin UI. An unmount can race the health check.

**Watcher state machine:**

```
:initializing
    ↓ media_dir accessible + watcher started
:watching                        ← normal, events forwarded
    ↓ :unmounted event OR stat fails
:media_dir_unavailable           ← all removal events suppressed; dashboard warning shown
    ↓ health check passes
:reconciling                     ← scan disk vs SQLite before resuming
    ↓ diff complete
:watching
```

**Reconciliation on remount:** When `media_dir` comes back, scan it and diff against `WatchedFile` records in SQLite. Only process a removal if a file is absent AND the drive is confirmed healthy. This catches files genuinely deleted while the drive was away. The `:file_system` watcher must also be re-initialised, as inotify watches do not survive unmount/remount cycles.

**Periodic health check:** The `Watcher` GenServer pings `media_dir` every 30 seconds. On any state change it broadcasts via `Phoenix.PubSub` so the dashboard shows a warning banner immediately.

### 3.2 Output Path Resilience (JSON writer / image downloader)

- **On startup:** check accessibility; if `media.json` is missing but SQLite has data → regenerate.
- **During writes:** if `shared_media_library` parent directory is unavailable, write fails with a logged error. The batcher retries on the next batch cycle.
- **If paths move:** update `shared_media_library` / `media_images_dir` in TOML → restart app → regenerate `media.json` at new path. Admin UI provides a "Regenerate library file" button.
- **Images:** remote `url` for every image is stored in SQLite. If images are missing (lost or new path), the admin UI can trigger a re-download of any or all images.

---

## 4. Pipeline Architecture

### 4.1 File Watching

`MediaManager.Watcher` (GenServer + `:file_system`) watches `media_dir` recursively. Subject to mount resilience rules in Section 3, it emits:

- `{:file_added, path}` — new file has stabilised (size stops changing; heuristic for completed torrent download)
- `{:file_removed, path}` — a tracked file is confirmed deleted on a healthy mount

### 4.2 Broadway Pipeline (addition path)

The pipeline is decoupled from the Watcher. The Watcher writes to the database; the Broadway pipeline reads from it via polling. See [`PIPELINE.md`](PIPELINE.md) for full implementation details.

```
Watcher (GenServer)
    │  detects file → :detect action → WatchedFile (:detected)
    │
Broadway Pipeline (MediaManager.Pipeline)
    │
    ├─ Producer (MediaManager.Pipeline.Producer)
    │    Polls DB every 10s for :detected files
    │    Claims each file atomically (:detected → :queued)
    │    Respects GenStage demand (fetches only what's needed)
    │
    └─ Processors (concurrency: 3)
         │
         ├─ :search action
         │    Calls TMDB search API via Req
         │    Computes confidence score for best match
         │    → :approved (high confidence) or :pending_review (low/no results)
         │
         ├─ :fetch_metadata action (only if :approved)
         │    Full TMDB fetch: details, cast, seasons, episodes (for TV)
         │    Creates Entity, Image, Identifier, Season, Episode records
         │    → :fetching_images
         │
         ├─ :download_images action (only if :fetching_images)
         │    Downloads artwork via Pipeline.ImageDownloader
         │    → :complete (best-effort; individual failures logged)
         │
         └─ :pending_review → stop (awaits human review in admin UI)
```

### 4.3 Removal Path

```
Watcher (only when media_dir confirmed healthy)
    │  {:file_removed, path}
    ▼
MediaManager.RemovalHandler (GenServer)
    │  Look up WatchedFile by file_path in SQLite
    │  If not found: no-op
    │
    ├─ Movie / VideoObject:
    │     Remove entity from SQLite
    │     Remove entity from media.json via JsonWriter
    │     Delete {media_images_dir}/{uuid}/ directory
    │
    └─ TVSeries episode file removed:
          Remove that episode from Season → Episode records in SQLite
          If no episodes remain in any season → remove whole TVSeries entity
          Regenerate TVSeries entry in media.json via JsonWriter
          Delete {media_images_dir}/{uuid}/ only if whole series removed
```

---

## 5. File Name Parsing (`MediaManager.Parser`)

Handles common torrent naming conventions via pattern-matched regex — no external library needed.

**Movie patterns:**

```
Movie.Name.YEAR.1080p.BluRay.x264-GROUP.mkv
Movie Name (YEAR).mkv
Movie Name YEAR.mkv
/path/to/Movie Name (YEAR)/movie.mkv   ← directory name used if file is generic
```

**TV patterns:**

```
Show.Name.S01E05.Episode.Title.1080p.mkv
Show Name - S01E05 - Episode Title.mkv
Show.Name.S01E05-06.mkv                 ← multi-episode (treat as first episode)
/Show Name/Season 1/S01E05 - Title.mkv  ← directory hints used
```

**Output struct:**

```elixir
%MediaManager.Parser.Result{
  file_path: String.t(),
  title: String.t(),           # cleaned, title-cased
  year: integer() | nil,
  type: :movie | :tv | :unknown,
  season: integer() | nil,
  episode: integer() | nil,
  episode_title: String.t() | nil
}
```

Unknown type → attempt TMDB movie search; falls back to `:pending_review` regardless of confidence.

---

## 6. Ash Resources (SQLite)

**Domain:** `MediaManager.Library`

**Enum types:** State and type fields use dedicated `Ash.Type.Enum` modules for compile-time safety:
- `MediaManager.Library.Types.EntityType` — `:movie`, `:tv_series`, `:video_object`
- `MediaManager.Library.Types.MediaType` — `:movie`, `:tv`, `:unknown` (parsed file type)
- `MediaManager.Library.Types.WatchedFileState` — all pipeline states

**Action policy:** Resources only expose purpose-built actions (no generic CRUD defaults). Each resource's `defaults` is limited to what the pipeline and UI actually need.

SQLite database lives at `~/.local/share/freedia-center/media-manager.db` (XDG data home, on system drive — separate from the shared media paths). This ensures it survives any output path or `media_dir` mount failures.

### `MediaManager.Library.WatchedFile`

Tracks every media file the pipeline knows about. One row per file. Multiple rows may point to the same `entity_id` (e.g. TV episode files → one TVSeries entity).

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `file_path` | string | Absolute path; unique index; used for removal lookup |
| `entity_id` | UUID (FK → Entity) | Assigned at Stage 4; nil until then |
| `parsed_title` | string | Output of name parser |
| `parsed_year` | integer | Output of name parser |
| `parsed_type` | `MediaType` enum | `:movie`, `:tv`, `:unknown` |
| `season_number` | integer | For TV episode files |
| `episode_number` | integer | For TV episode files |
| `tmdb_id` | string | Best TMDB candidate |
| `confidence_score` | float | Score of best TMDB match |
| `search_title` | string | Optional human override for TMDB search query; used instead of `parsed_title` when set |
| `state` | `WatchedFileState` enum | See state machine below |
| `error_message` | string | Set on `:error` state |
| `inserted_at` | utc_datetime | |
| `updated_at` | utc_datetime | |

**State machine:**

```
:detected → :queued → :searching → :pending_review → :approved (manual)
                                 → :approved (auto, high confidence)
                                      ↓
                                 :fetching_metadata → :fetching_images → :complete
                                                                        → :error
:complete → :removed  (file deleted, entity removed)
```

The `:queued` state is set by the Broadway pipeline producer when it claims a file for processing. This prevents duplicate processing in concurrent environments.

**Ash actions:**

| Action | Type | Description |
|--------|------|-------------|
| `:detect` | create | Parses `file_path`, sets `state: :detected`, populates parsed_* fields |
| `:detected_files` | read | Returns all files in `:detected` state, sorted by `inserted_at` ascending |
| `:claim` | update | Atomically transitions from `:detected` → `:queued`; fails if file is not in `:detected` state |
| `:search` | update | Calls TMDB search via `TMDB.Client`, scores results via `TMDB.Confidence`, sets `tmdb_id`, `confidence_score`, and transitions state to `:approved` or `:pending_review` |
| `:fetch_metadata` | update | Delegates to `EntityResolver` — fetches full TMDB details, creates `Entity` + `Image` + `Identifier` + `Season` + `Episode` records via `TMDB.Mapper`, transitions state to `:fetching_images` (new entity) or `:complete` (existing entity) |
| `:download_images` | update | Downloads artwork via `Pipeline.ImageDownloader`, transitions to `:complete` |

### `MediaManager.Library.Entity`

Canonical store for all library entity data. This is what `media.json` is generated from.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | The `@id` used in `media.json`; stable forever |
| `type` | `EntityType` enum | `:movie`, `:tv_series`, `:video_object` |
| `name` | string | |
| `description` | string | |
| `date_published` | string | Year or ISO date |
| `genres` | `{:array, :string}` | |
| `content_url` | string | Local playback path |
| `url` | string | Remote info page |
| `duration` | string | ISO 8601 (movies) |
| `director` | string | Movies |
| `content_rating` | string | Movies |
| `number_of_seasons` | integer | TVSeries |
| `aggregate_rating_value` | float | |
| `inserted_at` | utc_datetime | |
| `updated_at` | utc_datetime | |

**Associations:**

- `has_many :images, MediaManager.Library.Image`
- `has_many :identifiers, MediaManager.Library.Identifier`
- `has_many :seasons, MediaManager.Library.Season` (TVSeries only)
- `has_many :watched_files, MediaManager.Library.WatchedFile`

**Ash actions:**

| Action | Type | Description |
|--------|------|-------------|
| `:create_from_tmdb` | create | Creates an entity from scraped TMDB data; validates presence of `:type` and `:name`; accepts type, name, description, date_published, genres, url, duration, director, content_rating, number_of_seasons, aggregate_rating_value |
| `:set_content_url` | update | Sets the local playback `content_url` |
| `:with_associations` | read | Loads entity with all images, identifiers, watched_files, and seasons (with episodes) |
| `:destroy` | destroy | Used for race-loss cleanup when two processors create the same entity |

### `MediaManager.Library.Image`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `entity_id` | UUID (FK) | |
| `role` | string | `"poster"`, `"backdrop"`, `"logo"`, `"thumb"` |
| `url` | string | Remote source URL — populated at Stage 4 (metadata fetch); used for re-download |
| `content_url` | string or nil | Local path relative to `media_images_dir` — `nil` until Stage 5 (image download) completes |
| `extension` | string | `.jpg` or `.png` |

### `MediaManager.Library.Identifier`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `entity_id` | UUID (FK) | |
| `property_id` | string | `"tmdb"`, `"tvdb"`, etc. |
| `value` | string | External ID value |

### `MediaManager.Library.Season`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `entity_id` | UUID (FK → Entity) | |
| `season_number` | integer | 1-based |
| `number_of_episodes` | integer | |
| `name` | string | Optional season title |

**Associations:** `has_many :episodes, MediaManager.Library.Episode`

### `MediaManager.Library.Episode`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `season_id` | UUID (FK → Season) | |
| `episode_number` | integer | 1-based |
| `name` | string | |
| `description` | string | |
| `duration` | string | ISO 8601 |
| `content_url` | string | Local playback path |

**Associations:** `belongs_to :season, MediaManager.Library.Season`

---

## 7. TMDB API Usage

**Client:** `MediaManager.TMDB.Client` — uses `Req` with a cached `persistent_term` client to avoid rebuilding the request pipeline on every call. Each function accepts an optional `Req.Request` argument for testability.

**Mapper:** `MediaManager.TMDB.Mapper` — pure-function module that maps raw TMDB JSON responses to domain-ready attribute maps, isolating the API data shape from entity creation.

**Base URL:** `https://api.themoviedb.org/3`

**Auth:** `api_key` query parameter on every request (TMDB v3 auth)

**Search:**
- `GET /search/movie?query={title}&year={year}`
- `GET /search/tv?query={title}&first_air_date_year={year}`

**Details:**
- `GET /movie/{id}`
- `GET /tv/{id}`
- `GET /tv/{id}/season/{n}`

**Confidence scoring** (`MediaManager.TMDB.Confidence`):

1. Normalise result title vs parsed title (Jaro distance via `String.jaro_distance/2`)
2. Bonus (+0.08) if year matches
3. Bonus (+0.05) if it is the first result in the list
4. Score clamped to 0.0–1.0; compare against `auto_approve_threshold` (default 0.85)

**Image URL construction** (per `IMAGE-CACHING.md`):
`https://image.tmdb.org/t/p/original{path}` for poster, backdrop, logo.

---

## 8. `media.json` Write Strategy

`MediaManager.JsonWriter` is a singleton GenServer that serialises all writes.

**Write flow:**

1. Generate entity map from SQLite (`Entity` + associations)
2. Read current `media.json` (or `[]` if missing)
3. Find existing entry by `@id` (update) or append (new)
4. Encode → write to `media.json.tmp` → `File.rename/2` (atomic on Linux)
5. If `shared_media_library` parent directory unavailable → write fails, logged as error; batcher retries next cycle

**`JsonWriter.regenerate_all/0`** — reads all `:complete` `WatchedFile` entities from SQLite and rewrites `media.json` from scratch. Used after config changes (directory move, etc.) or when `media.json` is missing/corrupted.

**JSON format:** follows `DATA-FORMAT.md` exactly. Field names are schema.org identifiers.

---

## 9. Web UI (Admin Panel)

A lightweight Phoenix LiveView admin panel — local-only, no authentication.

**Router layout:**

```
GET /                → Dashboard LiveView   (activity feed, mount warnings, queue counts)
GET /review          → Review LiveView      (pending_review items inbox)
GET /review/:id      → Review Item LiveView (candidates, confirm/reject/search)
GET /library         → Library LiveView     (browse entities from SQLite)
GET /library/:id     → Library Item LiveView (detail, re-scrape, remove, re-download images)
```

**Dashboard warnings (via PubSub):**

- `media_dir` unavailable → red banner: "Media directory not accessible — removal events suppressed"
- `shared_media_library` parent directory unavailable → yellow banner: "Library file not writable — writes queued"

**Review flow:**

User sees: parsed title, year, TMDB candidates with poster thumbnails.

Actions: "Confirm" (top candidate), "Pick other", "Search manually", "Ignore".

On confirm → `WatchedFile` transitions to `:approved` → pipeline resumes at Stage 4.

**Library Item actions:**

- Re-scrape entity from TMDB
- Re-download images
- Remove entity (with confirmation)
- Regenerate `media.json` for this entity

---

## 10. Dependencies

| Package | Purpose | Already in mix.exs? |
|---------|---------|---------------------|
| `:file_system` | inotify-based file watching on Linux | No — add |
| `:broadway` | pipeline processing | No — add |
| `toml_elixir` | TOML config file parsing | No — add |
| `:ash_sqlite` | SQLite via Ash | Yes |
| `:ash` | resource framework | Yes |
| `:ash_phoenix` | LiveView integration | Yes |
| `:req` | HTTP client for TMDB | Yes |
| `:jason` | JSON encoding | Yes |

---

## 11. Open Questions / Future Work

- **Subtitle files:** Ignore `.srt`/`.ass` for now.
- **Re-scrape:** Trigger fresh TMDB fetch for existing entity — design in a later plan.
- **Multiple `media_dir` paths:** Array support is a TOML-compatible future extension.
- **In-progress torrent detection:** File size stability polling is a pragmatic heuristic; could be replaced with watching for `.part` file removal.
- **Image re-download UI:** Admin UI button to re-download all missing images for an entity.
- **TVDB/other sources:** TMDB only for now; TVDB support is a future extension.
