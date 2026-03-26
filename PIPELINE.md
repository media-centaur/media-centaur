# Pipeline Architecture

> **Last updated:** 2026-02-27

The media manager processes video files through an automated pipeline built on [Broadway](https://github.com/dashbitco/broadway). This document covers the pipeline's internal architecture — how files move from detection to completion.

For the data format produced at the end of the pipeline, see [`DATA-FORMAT.md`](specs/DATA-FORMAT.md). For image handling, see [`IMAGE-CACHING.md`](specs/IMAGE-CACHING.md).

---

## Overview

```
Watcher.Supervisor                     Broadway Pipeline
────────────────                       ─────────────────
starts one Watcher per watch_dir       Producer subscribes to PubSub "pipeline:input"
each Watcher detects files via         receives {:file_detected, %{path, watch_dir}}
  inotify + scan → broadcasts          Processor (concurrency 15, partitioned by file path):
  {:file_detected, ...} to PubSub  →     parse → search → fetch_metadata
                                          → download_images → ingest → link_file
                                          if needs_review → creates PendingFile (awaits UI)
```

The Watchers and Pipeline are decoupled via PubSub events. Watchers broadcast `{:file_detected, %{path, watch_dir}}` to `"pipeline:input"`; the Producer converts these into `%Payload{}` structs for Broadway processors. This separation means:

- Detection and processing run at independent rates
- Concurrency is controlled by Broadway (15 concurrent processors, partitioned by file path)
- Multiple directories can be watched independently
- Review-resolved files re-enter the pipeline via `{:review_resolved, ...}` PubSub events

---

## Payload

`MediaCentaur.Pipeline.Payload` is the data structure that flows through all pipeline stages. It accumulates results as it progresses:

| Field | Set by | Purpose |
|-------|--------|---------|
| `file_path` | Producer | Absolute path to the video file |
| `watch_directory` | Producer | Watch directory the file was found in |
| `entry_point` | Producer | `:file_detected` or `:review_resolved` |
| `parsed` | Parse stage | `%Parser.Result{}` with title, year, type, season, episode |
| `tmdb_id` | Search stage (or Producer for review_resolved) | TMDB ID of the matched entity |
| `tmdb_type` | Search stage (or Producer for review_resolved) | `:movie` or `:tv` |
| `confidence` | Search stage | Match confidence score (0.0–1.0) |
| `metadata` | FetchMetadata stage | Full TMDB metadata mapped to domain attributes |
| `staged_images` | DownloadImages stage | List of downloaded image files in staging directory |
| `entity_id` | Ingest stage | UUID of the created/found library entity |
| `pending_file_id` | Producer (review_resolved only) | PendingFile ID to clean up after completion |

---

## Components

### Producer (`MediaCentaur.Pipeline.Producer`)

A GenStage producer that subscribes to PubSub for pipeline input events.

**Behaviour:**
- Subscribes to `"pipeline:input"` PubSub topic on init
- Receives `{:file_detected, %{path, watch_dir}}` and `{:review_resolved, %{path, watch_dir, tmdb_id, tmdb_type, pending_file_id}}` messages
- Converts events to `%Payload{}` structs and queues them
- Dispatches payloads to Broadway processors on demand

**Source:** `lib/media_centaur/pipeline/producer.ex`

### Pipeline (`MediaCentaur.Pipeline`)

The Broadway module that orchestrates file processing.

**Configuration:**
- Producer concurrency: 1 (single PubSub subscriber)
- Processor concurrency: 15 (partitioned by file path)
- Batcher concurrency: 1 (serializes PubSub broadcasts), batch size 10, timeout 5s

**Processing flow per message:**

For `entry_point: :file_detected`:

1. Check if file is already linked to an entity (skip if so)
2. **Parse** — Extract title, year, type, season, episode from the file path
3. **Search** — Search TMDB for a match; score confidence
   - High confidence → continue to FetchMetadata
   - Low confidence → create PendingFile for review, stop
4. **FetchMetadata** — Fetch full TMDB details (movie, TV series, collection, season)
5. **DownloadImages** — Download artwork to a staging directory
6. **Ingest** — Create/update library Entity via `Library.Ingress`, move staged images to final location
7. **Link** — Create WatchedFile record (`:link_file` action, state `:complete`)
8. The Broadway **batcher** collects completed messages and broadcasts `{:entities_changed, entity_ids}` via PubSub

For `entry_point: :review_resolved`:

1. Parse the file path (no search needed — TMDB ID already known)
2. Run FetchMetadata → DownloadImages → Ingest → Link
3. Delete the PendingFile record and broadcast `{:file_reviewed, pending_file_id}`

**Error handling:** If any stage fails, the Broadway message is marked as failed with the error reason.

**Source:** `lib/media_centaur/pipeline.ex`

### Pipeline Stages

All stages are pure-function modules in `lib/media_centaur/pipeline/stages/`. Each takes a `%Payload{}` and returns `{:ok, payload}`, `{:needs_review, payload}`, or `{:error, reason}`.

| Stage | Module | Purpose |
|-------|--------|---------|
| Parse | `Pipeline.Stages.Parse` | Extracts title, year, type from file path via `Parser` |
| Search | `Pipeline.Stages.Search` | Searches TMDB, scores confidence, decides approve/review |
| FetchMetadata | `Pipeline.Stages.FetchMetadata` | Fetches full TMDB details, maps to domain metadata |
| DownloadImages | `Pipeline.Stages.DownloadImages` | Downloads artwork to staging directory |
| Ingest | `Pipeline.Stages.Ingest` | Creates/updates Entity via `Library.Ingress` |

---

## Supervision

The Pipeline is started as part of the application supervision tree, after the Watcher.Supervisor:

```elixir
children = [
  ...
  MediaCentaur.Watcher.Supervisor,
  {Task, &MediaCentaur.Watcher.Supervisor.start_watchers/0},
  MediaCentaur.Pipeline,
  MediaCentaurWeb.Endpoint
]
```

`Watcher.Supervisor` starts a `DynamicSupervisor` and a `Registry`. The init `Task` reads `Config.get(:watch_dirs)` and starts one `Watcher` child per directory. Each Watcher registers in the Registry with its directory path as key.

Broadway manages its own internal supervision tree (producer, processors, batchers). If the Pipeline crashes, the supervisor restarts it and it resumes listening for PubSub events.

### Scan

The dashboard provides a "Scan directories" button that triggers `Watcher.Supervisor.scan/0`. This walks all watched directories recursively, detecting video files not yet tracked. Each detected file is broadcast as a `{:file_detected, ...}` PubSub event, entering the pipeline normally.

---

## Idempotency & Concurrency Safety

The pipeline is designed to be safe to re-run and safe under concurrent processing:

- **Already-linked check:** Before processing, the Pipeline checks if the file path already has a WatchedFile with an entity. If so, the file is skipped.
- **WatchedFile deduplication:** The `unique_file_path` identity and upsert on `:link_file` prevent the same file from being tracked twice.
- **Entity deduplication:** `Library.Ingress` checks for an existing Entity by TMDB ID (via the `Identifier` resource's unique constraint on `(property_id, value)`). If found, the file is linked to the existing Entity with no new Entity created.
- **DB-level unique constraints:** Season (`entity_id, season_number`), Episode (`season_id, episode_number`), and Image (`entity_id, role`) all have unique indexes enforced by SQLite.
- **Upsert patterns:** All child record creation uses Ash `:find_or_create` actions with `upsert? true`. On conflict, the existing row is returned without modification.
- **Race-loss recovery:** If two processors both try to create an Entity for the same TMDB ID, the `Identifier` upsert detects the race. The loser destroys its orphan Entity and falls back to using the winner's Entity.
- **TV Season/Episode granularity:** Only Season and Episode records for files the user actually has are created — not all seasons/episodes from TMDB.
- **Batch PubSub broadcast:** Entity change notifications happen once per batch (up to 10 messages) via a Broadway batcher with concurrency 1.

---

## Extras (Bonus Features)

Movie extras (featurettes, behind-the-scenes, deleted scenes) are video files inside a subdirectory of a movie release — commonly named `Extras/`, `Featurettes/`, `Special Features/`, etc. The directory names are configurable via `extras_dirs` in `backend.toml`.

**Detection:** The parser (`MediaCentaur.Parser`) checks whether the file's parent directory name matches the configured extras list (case-insensitive) **before** running the normal candidate/pattern logic. When matched, it returns `type: :extra` with the cleaned filename as `title`, and the grandparent directory parsed as `parent_title` / `parent_year`.

**Pipeline flow for extras:**

1. **Parse** sets `parsed.type` to `:extra` with `parent_title` and `parent_year` extracted from the grandparent directory.
2. **Search** routes `:extra` to the `:movie` search path — extras share the parent movie's TMDB match.
3. **FetchMetadata** fetches the parent movie's metadata. **Ingest** creates the parent movie Entity (without setting `content_url` to the extra's file path) and creates an `Extra` record linking the bonus feature to the entity.
4. **DownloadImages** downloads artwork for the parent movie entity only — extras have no separate artwork.
5. **Serializer** outputs extras as `hasPart` containing `@type: "VideoObject"` entries within the parent Movie entity.

**Key invariant:** The parent movie's `content_url` is never set to the extra's file path. Only standalone movie files set `content_url` on the Entity. Extras get their own `content_url` in the `Extra` record.

---

## Review Flow

Files with low-confidence TMDB matches (or zero results) stop at `needs_review`. Discovery broadcasts `{:needs_review, attrs}` to `"review:intake"`. The `Review.Intake` GenServer subscribes and creates a `PendingFile` record for human review.

The `/review` admin UI surfaces these PendingFile records. The reviewer can:

1. **Approve** — Accepts the TMDB match. Broadcasts `{:file_matched, ...}` to `"pipeline:matched"`, which the Import pipeline picks up.
2. **Search** — Opens an inline TMDB search panel for manual matching, then approves with the selected result.
3. **Dismiss** — Rejects the file. The PendingFile is destroyed.

After Import finishes processing an approved file, it broadcasts `{:review_completed, pending_file_id}` to `"review:intake"`. The `Review.Intake` GenServer destroys the PendingFile and broadcasts `{:file_reviewed, id}` to `"review:updates"` so the Review UI updates.

All Pipeline ↔ Review communication uses PubSub — no direct cross-boundary function calls. PendingFile records are managed by the `Review` domain (`lib/media_centaur/review/`), separate from the `Library` domain.

---

## Future Stages

- **Dynamic directory management** — Add/remove watch directories at runtime via the admin UI without restart
- **Subtitle files** — Currently ignored (`.srt`/`.ass`); future extension
- **Re-scrape** — Trigger fresh TMDB fetch for an existing entity from the admin UI
- **In-progress torrent detection** — File size stability polling is a pragmatic heuristic; could be replaced with watching for `.part` file removal
- **TVDB/other sources** — TMDB only for now; TVDB support is a future extension
