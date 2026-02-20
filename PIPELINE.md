# Pipeline Architecture

> **Last updated:** 2026-02-20

The media manager processes video files through an automated pipeline built on [Broadway](https://github.com/dashbitco/broadway). This document covers the pipeline's internal architecture — how files move from detection to completion.

For the data format produced at the end of the pipeline, see [`DATA-FORMAT.md`](../specifications/DATA-FORMAT.md). For image handling, see [`IMAGE-CACHING.md`](../specifications/IMAGE-CACHING.md).

---

## Overview

```
Watcher (GenServer)                    Broadway Pipeline
─────────────────                      ─────────────────
detects file → :detect action          Producer polls DB every 10s
  creates WatchedFile (:detected)  →   finds :detected files, claims → :queued
                                       Processor (concurrency 3):
                                         :search → if approved → :fetch_metadata
                                         if pending_review → stop (awaits UI)
```

The Watcher and Pipeline are decoupled by design. The Watcher writes to the database; the Pipeline reads from it. This separation means:

- Detection and processing run at independent rates
- The Pipeline can be restarted without losing detected files
- Concurrency is controlled by Broadway (3 concurrent processors by default)
- Future stages (image download, serialization) slot in cleanly

---

## WatchedFile State Machine

```
:detected → :queued → :searching → :approved → :fetching_metadata → :fetching_images → :complete
                                 → :pending_review (low confidence; awaits UI)
                                 → :error
```

| State | Set by | Meaning |
|-------|--------|---------|
| `:detected` | Watcher via `:detect` action | File parsed, waiting for pipeline pickup |
| `:queued` | Producer via `:claim` action | Claimed by pipeline, in processing queue |
| `:searching` | `:search` action (change) | TMDB search in progress |
| `:approved` | `:search` action (change) | High-confidence match, auto-approved |
| `:pending_review` | `:search` action (change) | Low confidence or no results; needs human review |
| `:fetching_metadata` | `:fetch_metadata` action (change) | Fetching full TMDB details |
| `:fetching_images` | `:fetch_metadata` action (change) | Metadata stored, images pending download |
| `:complete` | Image download (not yet implemented) | Fully processed |
| `:error` | Any stage | Processing failed; `error_message` has details |
| `:removed` | Removal handler | Source file deleted |

---

## Components

### Producer (`MediaManager.Pipeline.Producer`)

A custom GenStage producer that feeds messages into Broadway.

**Behaviour:**
- Polls the database every 10 seconds (configurable via `:poll_interval` option)
- Respects GenStage demand — only fetches as many files as Broadway requests
- Reads files in `:detected` state via the `:detected_files` read action (sorted by `inserted_at` ascending — oldest first)
- Claims each file atomically via the `:claim` action, transitioning it from `:detected` to `:queued`
- If a claim fails (another process already claimed it), the file is skipped silently

**Claiming mechanism:** The `:claim` action validates that the file's state is still `:detected` before transitioning to `:queued`. This provides atomic, race-safe claiming — if two producers (or a restart) try to claim the same file, only one succeeds.

**Source:** `lib/media_manager/pipeline/producer.ex`

### Pipeline (`MediaManager.Pipeline`)

The Broadway module that orchestrates file processing.

**Configuration:**
- Producer concurrency: 1 (single poller is sufficient)
- Processor concurrency: 3 (limits parallel TMDB API calls)

**Processing flow per message:**

1. Call the `:search` action on the WatchedFile
   - Searches TMDB via `TMDB.Client`
   - Scores results via `TMDB.Confidence`
   - Transitions to `:approved` (high confidence) or `:pending_review` (low confidence / no results)
2. If the file reached `:approved`, call the `:fetch_metadata` action
   - Fetches full TMDB details (movie details or TV series + seasons + episodes)
   - Creates `Entity`, `Image`, `Identifier`, `Season`, and `Episode` records in SQLite
   - Transitions to `:fetching_images`
3. If the file reached `:pending_review`, processing stops — the file awaits human review in the admin UI

**Error handling:** If any action fails, the Broadway message is marked as failed with the error reason. The WatchedFile's state reflects where the failure occurred (`:searching`, `:error`, etc.).

**Source:** `lib/media_manager/pipeline.ex`

---

## Supervision

The Pipeline is started as part of the application supervision tree, after the Watcher:

```elixir
children = [
  ...
  MediaManager.Watcher,
  MediaManager.Pipeline,
  MediaManagerWeb.Endpoint
]
```

Broadway manages its own internal supervision tree (producer, processors, batchers). If the Pipeline crashes, the supervisor restarts it and it resumes polling — no detected files are lost because state is persisted in SQLite.

---

## Ash Actions

### `:detected_files` (read)

Returns all WatchedFiles in `:detected` state, sorted by `inserted_at` ascending.

### `:claim` (update)

Atomically transitions a WatchedFile from `:detected` to `:queued`. Fails if the file is not in `:detected` state (already claimed or processed).

### `:search` (update)

Searches TMDB for the file's parsed title/year. Sets `tmdb_id`, `confidence_score`, and transitions to `:approved` or `:pending_review`. On API error, transitions to `:error`.

### `:fetch_metadata` (update)

Fetches full TMDB metadata for an approved file. Creates associated records (Entity, Image, Identifier, Season, Episode). Transitions to `:fetching_images`.

---

## Future Stages

The pipeline is designed to be extended with additional processing stages:

- **Image download** — Download artwork to `{media_images_dir}/{uuid}/`, update `Image.content_url`, transition to `:complete`
- **JSON serialization** — Trigger `JsonWriter` to update `media.json` after metadata and images are ready
- **Re-processing** — After manual approval in the admin UI, the approved file can be re-queued for `:fetch_metadata`
