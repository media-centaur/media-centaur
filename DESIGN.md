# Media Manager — Application Design

> **Status:** Active (in development)
> **Last updated:** 2026-02-23

This document captures the full architecture of the `media-manager` Phoenix/Elixir application. Format contracts (entity schema, images, WebSocket API) are specified in `../specifications/`; this document covers app-internal design.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Configuration](#2-configuration)
3. [Mount Resilience](#3-mount-resilience)
4. [Pipeline Architecture](#4-pipeline-architecture)
5. [File Name Parsing](#5-file-name-parsing)
6. [Ash Resources (SQLite)](#6-ash-resources-sqlite)
7. [TMDB API Usage](#7-tmdb-api-usage)
8. [Web UI (Admin Panel)](#8-web-ui-admin-panel)
9. [Dependencies](#9-dependencies)
10. [Open Questions / Future Work](#10-open-questions--future-work)

---

## 1. Overview

The media manager is the **write-side** of Freedia Center. It watches configured `watch_dirs` for newly completed torrent downloads, identifies the content, scrapes metadata and artwork from external APIs, and serves the library to the `user-interface` over Phoenix Channels (WebSocket). It also maintains an image cache (at `media_images_dir`).

**SQLite is the canonical database.** All entity data (names, descriptions, genres, TMDB IDs, image remote URLs, season/episode structure) is stored in SQLite. The UI receives data via Phoenix Channels. This means:

- Moving output paths → update config, regenerate images, done
- Output paths become unavailable → app continues, writes queue, resume on reconnect
- Images lost → remote `url` stored in SQLite → re-download on demand

**Media types supported:** Movies, MovieSeries (collections), TVSeries (full episode metadata), VideoObject (fallback for unidentified content).

**Out of scope:** Games, subtitle management.

---

## 2. Configuration

**File:** `~/.config/freedia-center/media-manager.toml`

At startup, `MediaManager.Config` (a GenServer) reads this file and merges it over defaults from `defaults/media-manager.toml`. Values are accessible via `MediaManager.Config.get(:key)`.

```toml
# ~/.config/freedia-center/media-manager.toml

# Path to the SQLite database file.
database_path = "~/.local/share/freedia-center/media-manager.db"

# Directories containing video/media files (e.g. torrent downloads folders).
# Watched for additions and removals. May be on removable or network drives.
watch_dirs = ["/mnt/videos/Videos"]

# Directories to exclude from watching. Files inside these (and subdirectories)
# are ignored by both inotify and manual scans. Must be absolute paths.
exclude_dirs = []

# Directory for cached artwork images, one subdirectory per entity UUID.
media_images_dir = "~/.local/share/freedia-center/images"

[tmdb]
api_key = ""

[pipeline]
auto_approve_threshold = 0.85
extras_dirs = ["Extras", "Featurettes", "Special Features", "Behind The Scenes", "Bonus", "Deleted Scenes"]

[playback]
mpv_path = "/usr/bin/mpv"
socket_dir = "/tmp"
socket_timeout_ms = 5000
```

**TOML parsing:** `toml` library (in `mix.exs`).

**SQLite database location:** `~/.local/share/freedia-center/media-manager.db` (XDG data home, on system drive — separate from the shared media paths, so it survives any mount failure).

---

## 3. Mount Resilience

Both `watch_dirs` and the output path (`media_images_dir`) may reside on removable drives, NAS shares, or external mounts. The application must never lose library data due to a transient mount failure.

### 3.1 Watch Directory Resilience

The `Watcher` GenServer handles mount failures through two mechanisms:

- **Unmount detection.** inotify fires `IN_UNMOUNT` when a watched filesystem is ejected. The Watcher transitions to `:unavailable` state and stops forwarding events.
- **Burst detection.** If ≥50 removal events fire within 2 seconds, the Watcher logs a warning and broadcasts a suspicious burst event. An unmount can race the health check.

A periodic health check (every 30s) detects when the directory becomes accessible again and re-initialises the file system watcher.

### 3.2 Output Path Resilience

- **If paths move:** update `media_images_dir` in TOML → restart app. Admin UI can trigger re-download.
- **Images:** remote `url` for every image is stored in SQLite. If images are missing, the admin UI can trigger a re-download of any or all images.

---

## 4. Pipeline Architecture

### 4.1 File Watching

`MediaManager.Watcher` (GenServer + `:file_system`) watches each directory in `watch_dirs` recursively. Subject to mount resilience rules in Section 3, it detects new video files after size stability checks and creates `WatchedFile` records via the `:detect` action.

### 4.2 Broadway Pipeline

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
    │
    └─ Processors (concurrency: 3)
         │
         ├─ :search → TMDB search, confidence scoring
         │    → :approved (high confidence) or :pending_review
         │
         ├─ :fetch_metadata (if approved) → creates Entity + associations
         │    → :fetching_images (new) or :complete (existing)
         │
         └─ :download_images (new entities) → downloads artwork
              → :complete
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
  type: :movie | :tv | :extra | :unknown,
  season: integer() | nil,
  episode: integer() | nil,
  episode_title: String.t() | nil,
  parent_title: String.t() | nil,
  parent_year: integer() | nil
}
```

Unknown type → attempt TMDB movie search; falls back to `:pending_review` regardless of confidence.

---

## 6. Ash Resources (SQLite)

**Domain:** `MediaManager.Library`

**Enum types:** State and type fields use dedicated `Ash.Type.Enum` modules for compile-time safety:
- `MediaManager.Library.Types.EntityType` — `:movie`, `:movie_series`, `:tv_series`, `:video_object`
- `MediaManager.Library.Types.MediaType` — `:movie`, `:tv`, `:extra`, `:unknown` (parsed file type)
- `MediaManager.Library.Types.WatchedFileState` — all pipeline states

**Action policy:** Resources only expose purpose-built actions (no generic CRUD defaults). Each resource's `defaults` is limited to what the pipeline and UI actually need.

SQLite database lives at `~/.local/share/freedia-center/media-manager.db` (XDG data home, on system drive — separate from the shared media paths). This ensures it survives any output path or `watch_dirs` mount failures.

### `MediaManager.Library.WatchedFile`

Tracks every media file the pipeline knows about. One row per file. Multiple rows may point to the same `entity_id` (e.g. TV episode files → one TVSeries entity).

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | Primary key |
| `file_path` | string | Absolute path; unique index; used for removal lookup |
| `entity_id` | UUID (FK → Entity) | Assigned at Stage 4; nil until then |
| `parsed_title` | string | Output of name parser |
| `parsed_year` | integer | Output of name parser |
| `parsed_type` | `MediaType` enum | `:movie`, `:tv`, `:extra`, `:unknown` |
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

Canonical store for all library entity data. Served to the UI via Phoenix Channels.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | The `@id` used in channel messages; stable forever |
| `type` | `EntityType` enum | `:movie`, `:movie_series`, `:tv_series`, `:video_object` |
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
- `has_many :movies, MediaManager.Library.Movie` (MovieSeries child movies)
- `has_many :extras, MediaManager.Library.Extra`
- `has_many :seasons, MediaManager.Library.Season` (TVSeries only)
- `has_many :watched_files, MediaManager.Library.WatchedFile`
- `has_many :watch_progress, MediaManager.Library.WatchProgress`

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
| `property_id` | string | `"tmdb"`, `"tmdb_collection"`, `"tvdb"`, etc. |
| `value` | string | External ID value |

### `MediaManager.Library.Movie`

Child movie within a MovieSeries (collection).

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `entity_id` | UUID (FK → Entity) | Parent movie series |
| `name` | string | |
| `date_published` | string | Year or ISO date |
| `content_url` | string | Local playback path |
| `position` | integer | Sort order within the collection |

**Associations:** `belongs_to :entity`, `has_many :images`

### `MediaManager.Library.Season`

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `entity_id` | UUID (FK → Entity) | |
| `season_number` | integer | 1-based |
| `number_of_episodes` | integer | |
| `name` | string | Optional season title |

**Associations:** `has_many :episodes`, `has_many :extras`

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

**Associations:** `belongs_to :season`, `has_many :images`

### `MediaManager.Library.Extra`

Bonus features linked to an entity or a specific season.

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `entity_id` | UUID (FK → Entity) | |
| `season_id` | UUID (FK → Season) | Optional — if set, extra belongs to a season |
| `name` | string | |
| `content_url` | string | Local playback path |
| `position` | integer | Sort order |

### `MediaManager.Library.WatchProgress`

Tracks watch progress per entity, per episode (for TV series) or per entity (for movies).

| Field | Type | Notes |
|-------|------|-------|
| `id` | UUID | |
| `entity_id` | UUID (FK → Entity) | |
| `season_number` | integer | nil for movies |
| `episode_number` | integer | nil for movies |
| `position_seconds` | float | Playback position |
| `duration_seconds` | float | Total duration |
| `completed` | boolean | |
| `last_watched_at` | utc_datetime | |

### `MediaManager.Library.Setting`

Key-value store for application settings persisted in SQLite (e.g. log component toggles).

| Field | Type | Notes |
|-------|------|-------|
| `key` | string | Primary key |
| `value` | map | JSON-encoded value |

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
- `GET /collection/{id}`

**Confidence scoring** (`MediaManager.TMDB.Confidence`):

1. Normalise result title vs parsed title (Jaro distance via `String.jaro_distance/2`)
2. Bonus (+0.08) if year matches
3. Bonus (+0.05) if it is the first result in the list
4. Score clamped to 0.0–1.0; compare against `auto_approve_threshold` (default 0.85)

**Image URL construction** (per `IMAGE-CACHING.md`):
`https://image.tmdb.org/t/p/original{path}` for poster, backdrop, logo.

---

## 8. Web UI (Admin Panel)

A lightweight Phoenix LiveView admin panel — local-only, no authentication.

**Router layout:**

```
GET /          → DashboardLive   (activity feed, watcher health, queue counts, playback status)
GET /review    → ReviewLive      (pending_review items inbox — approve, search, retry, dismiss)
GET /library   → LibraryLive     (browse entities, play media, view episode/movie details)
GET /logging   → LoggingLive     (toggle component thinking logs and framework log suppression)
```

---

## 9. Dependencies

| Package | Purpose |
|---------|---------|
| `:ash` | Resource framework |
| `:ash_sqlite` | SQLite via Ash |
| `:ash_phoenix` | LiveView integration |
| `:ash_ai` | LLM features for Ash |
| `:phoenix` | Web framework |
| `:phoenix_live_view` | LiveView |
| `:phoenix_live_dashboard` | Dev dashboard |
| `:req` | HTTP client for TMDB |
| `:jason` | JSON encoding |
| `:file_system` | inotify-based file watching |
| `:broadway` | Pipeline processing |
| `:toml` | TOML config file parsing |
| `:bandit` | HTTP server |

---

## 10. Open Questions / Future Work

- **Subtitle files:** Ignore `.srt`/`.ass` for now.
- **Re-scrape:** Trigger fresh TMDB fetch for existing entity — design in a later plan.
- **In-progress torrent detection:** File size stability polling is a pragmatic heuristic; could be replaced with watching for `.part` file removal.
- **TVDB/other sources:** TMDB only for now; TVDB support is a future extension.
