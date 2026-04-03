# Pipeline Architecture

> **Last updated:** 2026-03-26

The media manager processes video files through three Broadway pipelines: **Discovery**, **Import**, and **Image**. All cross-pipeline communication uses PubSub events — no direct function calls.

For the data format produced at the end of the pipeline, see [`DATA-FORMAT.md`](specs/DATA-FORMAT.md). For image handling, see [`IMAGE-CACHING.md`](specs/IMAGE-CACHING.md).

---

## Overview

```
Watcher                      Discovery Pipeline              Import Pipeline
────────                     ──────────────────              ───────────────
detects files via            parse → search                  fetch_metadata → ingest
inotify + scan               high confidence → matched       → publish entity event
  ↓                          low confidence → needs_review    → Library.Inbound creates records
"pipeline:input"         →  "pipeline:matched"           →  "pipeline:publish"
                                                               ↓
                             Review UI                      Image Pipeline
                             ─────────                      ──────────────
                             approve/search/dismiss         download → resize → write
                               ↓                              ↓
                             "pipeline:matched"             "pipeline:publish"
                                                            → Library.Inbound creates Image records
```

---

## PubSub Event Flow

| Topic | Producer | Consumer | Payload |
|-------|----------|----------|---------|
| `pipeline:input` | Watcher | Discovery.Producer | `{:file_detected, %{path, watch_dir}}` |
| `pipeline:matched` | Discovery, Review | Import.Producer | `{:file_matched, %{file_path, watch_dir, tmdb_id, tmdb_type, pending_file_id}}` |
| `pipeline:publish` | Import (Ingest stage), ImagePipeline | Library.Inbound | `{:entity_published, event}`, `{:image_ready, attrs}` |
| `pipeline:images` | Library.Inbound | ImagePipeline.Producer | `{:images_pending, %{entity_id, watch_dir}}` |
| `review:intake` | Discovery, Import | Review.Intake | `{:needs_review, attrs}`, `{:review_completed, id}`, `{:files_for_review, files}` |
| `review:updates` | Review.Intake | LiveViews | `{:file_added, id}`, `{:file_reviewed, id}` |
| `library:updates` | Library.Inbound, Watcher | LiveViews, Channels | `{:entities_changed, entity_ids}` |
| `library:commands` | Review.Rematch | Library.Inbound | `{:rematch_requested, entity_id}` |

---

## Payload

`MediaCentaur.Pipeline.Payload` is the data structure that flows through all pipeline stages:

| Field | Set by | Purpose |
|-------|--------|---------|
| `file_path` | Producer | Absolute path to the video file |
| `watch_directory` | Producer | Watch directory the file was found in |
| `entry_point` | Producer | `:file_detected` or `:review_resolved` |
| `parsed` | Parse stage | `%Parser.Result{}` with title, year, type, season, episode |
| `tmdb_id` | Search stage (or Producer) | TMDB ID of the matched entity |
| `tmdb_type` | Search stage (or Producer) | `:movie` or `:tv` |
| `confidence` | Search stage | Match confidence score (0.0–1.0) |
| `metadata` | FetchMetadata stage | Full TMDB metadata mapped to domain attributes |
| `entity_id` | Ingest stage | UUID of the created/found library entity |
| `pending_images` | Ingest stage | List of images to download |
| `pending_file_id` | Producer (review_resolved only) | PendingFile ID to clean up after completion |

---

## Discovery Pipeline

**Module:** `MediaCentaur.Pipeline.Discovery`

Identifies what a file is — parses the filename, searches TMDB, and decides if it's a confident match or needs human review.

**Configuration:**
- Producer: `Discovery.Producer` (PubSub subscriber to `"pipeline:input"`)
- Processors: 10 concurrent, partitioned by file path
- Batcher: 1, batch size 10, timeout 5s

**Processing flow:**
1. **Dedup check** — query `library_watched_files` directly (not through Library context) to skip already-linked files
2. **Parse** — extract title, year, type, season, episode from the file path
3. **Search** — search TMDB, score confidence
   - High confidence → batcher emits `{:file_matched, ...}` to `"pipeline:matched"`
   - Low confidence → broadcast `{:needs_review, attrs}` to `"review:intake"`, stop

---

## Import Pipeline

**Module:** `MediaCentaur.Pipeline.Import`

Fetches full metadata for a matched file and publishes the entity event for Library to create records.

**Configuration:**
- Producer: `Import.Producer` (PubSub subscriber to `"pipeline:matched"`)
- Processors: 5 concurrent, partitioned by file path
- Batcher: 1, batch size 10, timeout 5s

**Processing flow:**
1. **Parse** — re-parse the file path (Import may receive files from Discovery or Review)
2. **FetchMetadata** — fetch full TMDB details (movie, TV series, collection, season)
3. **Ingest** — broadcast `{:entity_published, event}` to `"pipeline:publish"`

After ingest, `Library.Inbound` subscribes and handles: entity creation/linking, child records (seasons, episodes, movies, extras), external ID creation, WatchedFile linking, and image queue population.

If the file came from review approval, Import also broadcasts `{:review_completed, pending_file_id}` to `"review:intake"`.

---

## Image Pipeline

**Module:** `MediaCentaur.ImagePipeline`

Downloads and processes artwork asynchronously after entity creation.

**Configuration:**
- Producer: PubSub subscriber to `"pipeline:images"`
- Processors: 4 concurrent (moderate to avoid TMDB CDN hammering)

**Processing flow:**
1. Query `pipeline_image_queue` for pending entries
2. Download from TMDB CDN
3. Resize to target dimensions per role (poster, backdrop, logo, thumb)
4. Write to disk under the entity's image directory
5. Broadcast `{:image_ready, attrs}` to `"pipeline:publish"` → `Library.Inbound` creates Image records

**Queue table:** `pipeline_image_queue` tracks source URL, owner metadata, retry state. Entries are created by `Library.Inbound` after entity creation.

---

## Pipeline Stages

All stages are pure-function modules in `lib/media_centaur/pipeline/stages/`. Each takes a `%Payload{}` and returns `{:ok, payload}`, `{:needs_review, payload}`, or `{:error, reason}`.

| Stage | Module | Used by | Purpose |
|-------|--------|---------|---------|
| Parse | `Stages.Parse` | Discovery, Import | Extracts title, year, type from file path via `Parser` |
| Search | `Stages.Search` | Discovery | Searches TMDB, scores confidence, decides approve/review |
| FetchMetadata | `Stages.FetchMetadata` | Import | Fetches full TMDB details, maps to domain metadata |
| Ingest | `Stages.Ingest` | Import | Broadcasts entity event to `"pipeline:publish"` |

---

## Supervision

```
MediaCentaur.Supervisor
├── Pipeline.Supervisor (:rest_for_one)
│   ├── Pipeline.Stats (telemetry)
│   ├── Pipeline.Discovery (Broadway)
│   └── Pipeline.Import (Broadway)
├── ImagePipeline.Supervisor (:rest_for_one)
│   ├── Pipeline.Stats (shared)
│   └── ImagePipeline (Broadway)
└── ...
```

If Stats crashes, pipelines restart (telemetry re-attach). Pipeline crashes do not affect Stats.

Watchers and pipelines can be independently stopped/started via config (`start_watchers`, `start_pipeline`).

---

## Idempotency & Concurrency Safety

- **Already-linked check:** Discovery queries `library_watched_files` directly to skip files already linked to entities
- **Entity deduplication:** `Library.Inbound` checks for existing entities by TMDB ID via the `ExternalId` unique constraint on `(source, external_id)`
- **Race-loss recovery:** If two processors create entities for the same TMDB ID, the `ExternalId` insert detects the race; the loser destroys its orphan entity
- **Find-or-create patterns:** Season, Episode, Movie, and Extra creation uses find-or-create — existing records are returned without modification
- **DB-level constraints:** Season `(entity_id, season_number)`, Episode `(season_id, episode_number)`, Image `(entity_id, role)` — all have unique indexes
- **Image queue dedup:** Queue entries track owner + role; duplicates are prevented at insert

---

## Extras (Bonus Features)

Extras (featurettes, behind-the-scenes, deleted scenes) are detected by the Parser when a file's parent directory matches configured extras directory names.

**Flow:** Parse sets `type: :extra` → Search routes to parent movie match → FetchMetadata fetches parent metadata → Ingest creates parent Entity (without `content_url`) + Extra record → Entity `content_url` is never set to the extra's file path.

---

## Review Flow

Files with low-confidence TMDB matches stop at Discovery. Discovery broadcasts `{:needs_review, attrs}` to `"review:intake"`. `Review.Intake` creates a PendingFile for human review.

The `/review` UI surfaces PendingFiles. The reviewer can:
1. **Approve** — accepts the match, broadcasts `{:file_matched, ...}` to `"pipeline:matched"` → Import processes it
2. **Search** — manual TMDB search, then approve with selected result
3. **Dismiss** — destroys the PendingFile

After Import finishes, it broadcasts `{:review_completed, pending_file_id}` to `"review:intake"` → Intake destroys the PendingFile.

**Rematch:** From the Library UI, a user can rematch an entity. `Review.Rematch` broadcasts `{:rematch_requested, entity_id}` to `"library:commands"`. `Library.Inbound` destroys the entity and sends `{:files_for_review, files}` to `"review:intake"` → Intake creates PendingFiles for re-review.

All Pipeline ↔ Review ↔ Library communication uses PubSub — no direct cross-context function calls.
