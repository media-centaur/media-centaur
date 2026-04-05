# Pipeline Architecture

> **Last updated:** 2026-04-05

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
| `parsed` | Parse stage | `%Parser.Result{}` with title, year, type, season, episode |
| `tmdb_id` | Search stage (or Import Producer for review-resolved files) | TMDB ID of the matched entity |
| `tmdb_type` | Search stage (or Import Producer) | `:movie` or `:tv` |
| `confidence` | Search stage | Match confidence score (0.0–1.0) |
| `match_title` / `match_year` / `match_poster_path` / `candidates` | Search stage | Display-oriented match fields + scored candidate list, used when the file falls out to review |
| `metadata` | FetchMetadata stage | Full TMDB metadata mapped to domain attributes |
| `entity_id` | Ingest stage (via `Library.Inbound.ingest/1`) | UUID of the created/found library entity |
| `ingest_status` | Ingest stage | `:new`, `:new_child`, or `:existing` |
| `pending_images` | Ingest stage | List of images to download |
| `pending_file_id` | Import Producer (review-resolved files only) | PendingFile ID to clean up after Import finishes |

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
1. **Parse** — re-parse the file path directly via `Parser.parse/2` (Import may receive files from Discovery or Review, so it always re-parses)
2. **Disk space check** — aborts with `{:error, :insufficient_disk_space}` if the image directory's filesystem has less than 100 MB free
3. **FetchMetadata** — fetch full TMDB details (movie, TV series, collection, season)
4. **Ingest** — broadcast `{:entity_published, event}` to `"pipeline:publish"`

After ingest, `Library.Inbound` subscribes and handles: entity creation/linking, child records (seasons, episodes, movies, extras), external ID creation, WatchedFile linking, and image queue population.

If the file came from review approval, Import also broadcasts `{:review_completed, pending_file_id}` to `"review:intake"`.

---

## Image Pipeline

**Module:** `MediaCentaur.ImagePipeline`

Downloads and processes artwork asynchronously after entity creation.

**Configuration:**
- Producer: PubSub subscriber to `"pipeline:images"`; dispatches queue entries as Broadway messages
- Processors: 4 concurrent (moderate to avoid TMDB CDN hammering)
- Batcher: 1, batch size 20, timeout 5s (collects completed downloads for one `library:updates` broadcast per batch)

**Processing flow:**
1. Producer pulls pending entries from `pipeline_image_queue` on `{:images_pending, ...}` events
2. Processor downloads and resizes in one step via `ImageProcessor.download_and_resize/3` (target dimensions per role: poster, backdrop, logo, thumb)
3. Writes the resized image to disk under the entity's image directory
4. Batcher marks queue entries `:complete`, broadcasts `{:image_ready, attrs}` to `"pipeline:publish"` (→ `Library.Inbound` creates/updates `Library.Image` records), and calls `Library.broadcast_entities_changed/1` so LiveViews see the new artwork

**Failure handling:** `handle_failed/2` classifies failures as `:permanent` (4xx responses, malformed URLs — marks the queue entry `:permanent`, never retries) or `:transient` (network errors, 5xx — delegates to `ImageQueue.mark_failed/1`, which `ImagePipeline.RetryScheduler` picks up on its next tick).

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
│   ├── ImagePipeline.Stats (telemetry — separate from Pipeline.Stats)
│   ├── ImagePipeline (Broadway)
│   └── ImagePipeline.RetryScheduler
└── ...
```

If Stats crashes, the pipelines in its supervisor restart (clean telemetry re-attach). Pipeline crashes do not affect Stats.

`ImagePipeline.RetryScheduler` periodically retries transient image download failures (network errors, CDN hiccups). Permanent failures (4xx responses, invalid URLs) are marked once and never retried — see `handle_failed/2` in `ImagePipeline`.

Watchers and pipelines can be independently stopped/started via config (`start_watchers`, `start_pipeline`).

**Startup reconciliation (ADR-023):** When `Discovery.Producer` starts, it sends itself `:reconcile` and triggers `Watcher.Supervisor.scan()` under the Task.Supervisor. This re-detects files that appeared while the pipeline was down so no work is lost across restarts.

---

## Idempotency & Concurrency Safety

- **Already-linked check:** Discovery queries `library_watched_files` directly (via the `WatchedFile` schema + Repo, not through the Library context) to skip files that are already linked to an entity. A file is "linked" when any one of `movie_id`, `tv_series_id`, `movie_series_id`, `video_object_id` is set.
- **Entity deduplication:** `Library.Inbound` looks up existing entities by TMDB ID via `Library.ExternalId`, which has a unique constraint on `(source, external_id)`
- **Race-loss recovery:** If two processors create entities for the same TMDB ID, the `ExternalId` insert detects the race; the loser destroys its orphan entity
- **Find-or-create patterns:** Season, Episode, Movie, and Extra creation uses find-or-create — existing records are returned without modification
- **DB-level constraints:** `library_images` has per-owner-type unique indexes on `(owner_id, role)` for each new type (`tv_series_id`, `movie_series_id`, `video_object_id`). Episode-number uniqueness is enforced by find-or-create in code.
- **Image queue dedup:** Queue entries track owner + role; duplicates are prevented at insert

---

## Extras (Bonus Features)

Extras (featurettes, behind-the-scenes, deleted scenes) are detected by the Parser when a file's parent directory matches configured extras directory names.

**Flow:** Parse sets `type: :extra` → Search routes to the parent movie match → FetchMetadata fetches parent metadata → Ingest creates the parent record (Movie / TVSeries / MovieSeries, without `content_url`) plus an `Extra` row linked via the type-specific FK → the parent record's `content_url` is never set to the extra's file path.

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
