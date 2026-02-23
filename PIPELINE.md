# Pipeline Architecture

> **Last updated:** 2026-02-23

The media manager processes video files through an automated pipeline built on [Broadway](https://github.com/dashbitco/broadway). This document covers the pipeline's internal architecture — how files move from detection to completion.

For the data format produced at the end of the pipeline, see [`DATA-FORMAT.md`](../specifications/DATA-FORMAT.md). For image handling, see [`IMAGE-CACHING.md`](../specifications/IMAGE-CACHING.md).

---

## Overview

```
Watcher.Supervisor                     Broadway Pipeline
────────────────                       ─────────────────
starts one Watcher per watch_dir       Producer polls DB every 2s
each Watcher detects files via         finds :detected + stale :queued, claims → :queued
  inotify + scan → :detect action      Processor (concurrency 15, partitioned by entity):
  creates WatchedFile (:detected)  →     :search → if approved → :fetch_metadata
                                         → :download_images → :complete
                                         if pending_review → stop (awaits UI)
```

The Watchers and Pipeline are decoupled by design. The Watchers write to the database; the Pipeline reads from it. This separation means:

- Detection and processing run at independent rates
- The Pipeline can be restarted without losing detected files
- Concurrency is controlled by Broadway (15 concurrent processors, partitioned by entity)
- Multiple directories can be watched independently

---

## WatchedFile State Machine

```
:detected → :queued → :searching → :approved → :fetching_metadata → :fetching_images → :complete
                                 → :pending_review (low confidence; awaits UI)
                                    → :approved (manual approval via review UI)
                                    → :dismissed (user-initiated rejection via review UI)
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
| `:complete` | `:download_images` action (change) | Fully processed, images downloaded |
| `:error` | Any stage | Processing failed; `error_message` has details |
| `:removed` | Removal handler | Source file deleted |
| `:dismissed` | Review UI via `:dismiss` action | User rejected the file; terminal state |

---

## Components

### Producer (`MediaManager.Pipeline.Producer`)

A custom GenStage producer that feeds messages into Broadway.

**Behaviour:**
- Polls the database every 2 seconds (configurable via `@poll_interval`)
- Respects GenStage demand — only fetches as many files as Broadway requests
- Reads files via the `:claimable_files` read action, which returns files in `:detected` state **and** stale `:queued` files (older than 5 minutes) for crash recovery
- Claims each file atomically via the `:claim` action, transitioning it from `:detected` to `:queued`
- If a claim fails (another process already claimed it), the file is skipped silently

**Claiming mechanism:** The `:claim` action validates that the file's state is still `:detected` before transitioning to `:queued`. This provides atomic, race-safe claiming — if two producers (or a restart) try to claim the same file, only one succeeds.

**Crash recovery:** On startup and during normal polling, the Producer also reclaims files stuck in `:queued` state from a previous crash. Files that have been `:queued` for longer than 5 minutes (`@stale_threshold_minutes`) are treated as abandoned and included in the claimable set.

**Source:** `lib/media_manager/pipeline/producer.ex`

### Pipeline (`MediaManager.Pipeline`)

The Broadway module that orchestrates file processing.

**Configuration:**
- Producer concurrency: 1 (single poller is sufficient)
- Processor concurrency: 15 (partitioned by entity to prevent concurrent processing of the same entity)
- Batcher concurrency: 1 (serializes PubSub broadcasts), batch size 10, timeout 5s

**Processing flow per message:**

1. Call the `:search` action on the WatchedFile
   - Searches TMDB via `TMDB.Client`
   - Scores results via `TMDB.Confidence`
   - Transitions to `:approved` (high confidence) or `:pending_review` (low confidence / no results)
2. If the file reached `:approved`, call the `:fetch_metadata` action
   - Delegates to `EntityResolver.resolve/3`, which orchestrates entity find-or-create
   - Checks if an Entity with the same TMDB ID already exists (via `Identifier`)
   - **If entity exists (movie):** links the WatchedFile to the existing Entity and transitions directly to `:complete` (images already downloaded)
   - **If entity exists (TV):** links the WatchedFile to the existing Entity, ensures the Season/Episode record exists, and transitions to `:fetching_images` (episode thumbnails may need downloading)
   - **If entity is new:** fetches full TMDB details via `TMDB.Client`, maps responses to domain attributes via `TMDB.Mapper`, creates `Entity`, `Image`, `Identifier` records, and (for TV) only the Season and Episode matching this file — not all seasons/episodes from TMDB. Transitions to `:fetching_images`
   - Sets `content_url` on the Entity (movies) or Episode (TV) to the video file path
3. If the file reached `:fetching_images`, call the `:download_images` action
   - Downloads artwork from TMDB CDN via `Pipeline.ImageDownloader.download_all/1`
   - Writes files to `{media_images_dir}/{entity-uuid}/{role}.{ext}`
   - Updates `Image` records' `content_url` with the local relative path
   - Individual image failures are logged as warnings but do not block completion — all downloadable images are attempted
   - Always transitions to `:complete`
4. The Broadway **batcher** (concurrency 1, batch size 10, timeout 5s) collects completed messages and broadcasts `{:entities_changed, entity_ids}` via PubSub (pushing to connected UIs over Phoenix Channels)
5. If the file reached `:pending_review`, processing stops — the file awaits human review in the admin UI

**Error handling:** If any action fails, the Broadway message is marked as failed with the error reason. The WatchedFile's state reflects where the failure occurred (`:searching`, `:error`, etc.).

**Source:** `lib/media_manager/pipeline.ex`

---

## Supervision

The Pipeline is started as part of the application supervision tree, after the Watcher.Supervisor:

```elixir
children = [
  ...
  MediaManager.Watcher.Supervisor,
  {Task, &MediaManager.Watcher.Supervisor.start_watchers/0},
  MediaManager.Pipeline,
  MediaManagerWeb.Endpoint
]
```

`Watcher.Supervisor` starts a `DynamicSupervisor` and a `Registry`. The init `Task` reads `Config.get(:watch_dirs)` and starts one `Watcher` child per directory. Each Watcher registers in the Registry with its directory path as key.

Broadway manages its own internal supervision tree (producer, processors, batchers). If the Pipeline crashes, the supervisor restarts it and it resumes polling — no detected files are lost because state is persisted in SQLite.

### Scan

The dashboard provides a "Scan directories" button that triggers `Watcher.Supervisor.scan/0`. This walks all watched directories recursively, detecting video files not yet tracked. This is useful for files that were already present when the app started (inotify only catches new events).

---

## Ash Actions

### `:claimable_files` (read)

Returns WatchedFiles eligible for pipeline pickup: files in `:detected` state, plus files stuck in `:queued` state longer than the stale threshold (5 minutes). Sorted by `inserted_at` ascending.

### `:claim` (update)

Atomically transitions a WatchedFile from `:detected` to `:queued`. Fails if the file is not in `:detected` state (already claimed or processed).

### `:search` (update)

Searches TMDB for the file's parsed title/year. Sets `tmdb_id`, `confidence_score`, and transitions to `:approved` or `:pending_review`. On API error, transitions to `:error`.

### `:fetch_metadata` (update)

Fetches full TMDB metadata for an approved file. **Idempotent:** if an Entity with the same TMDB ID already exists, the WatchedFile is linked to the existing Entity. For existing movie entities, transitions directly to `:complete` (images already downloaded). For existing TV entities, transitions to `:fetching_images` (episode thumbnails may need downloading). If no existing Entity is found, creates Entity, Image, Identifier, and (for TV series) only the Season/Episode matching the scanned file. Transitions to `:fetching_images` for new entities.

### `:download_images` (update)

Downloads artwork for all `Image` records with a `url` but no `content_url` via `Pipeline.ImageDownloader`. Writes files to `{media_images_dir}/{entity-uuid}/{role}.{ext}`, updates `Image.content_url`. Individual image failures are logged but do not block completion — all images are attempted. Always transitions to `:complete`.

---

## Idempotency & Concurrency Safety

The pipeline is designed to be safe to re-run and safe under concurrent processing. Scanning the same directories multiple times produces the same result, even with 15 concurrent processors:

- **WatchedFile deduplication:** The `unique_file_path` identity prevents the same file from being tracked twice.
- **Entity deduplication:** `EntityResolver` (called by `FetchMetadata`) checks for an existing Entity by TMDB ID (via the `Identifier` resource's `unique_external_id` identity on `(property_id, value)`). If found, the WatchedFile is linked to the existing Entity with no new records created.
- **DB-level unique constraints:** Season (`entity_id, season_number`), Episode (`season_id, episode_number`), and Image (`entity_id, role`) all have unique indexes enforced by SQLite. These prevent duplicate records regardless of concurrency.
- **Upsert patterns:** All child record creation uses Ash `:find_or_create` actions with `upsert? true`. On conflict, the existing row is returned without modification. This replaces the previous read-then-write pattern which was racy.
- **Race-loss recovery:** If two processors both try to create an Entity for the same TMDB ID, the `Identifier` upsert detects the race. The loser destroys its orphan Entity and falls back to using the winner's Entity (treating it as `:existing`).
- **TV Season/Episode granularity:** Only Season and Episode records for files the user actually has are created — not all seasons/episodes from TMDB. Additional episode files for the same series add to the existing Entity.
- **Image download skip:** When reusing an existing Entity, images are already downloaded. The WatchedFile transitions directly to `:complete`, skipping `DownloadImages`.
- **Batch PubSub broadcast:** Entity change notifications happen once per batch (up to 10 messages) via a Broadway batcher with concurrency 1, avoiding redundant broadcasts.

---

## Extras (Bonus Features)

Movie extras (featurettes, behind-the-scenes, deleted scenes) are video files inside a subdirectory of a movie release — commonly named `Extras/`, `Featurettes/`, `Special Features/`, etc. The directory names are configurable via `extras_dirs` in `media-manager.toml`.

**Detection:** The parser (`MediaManager.Parser`) checks whether the file's parent directory name matches the configured extras list (case-insensitive) **before** running the normal candidate/pattern logic. When matched, it returns `type: :extra` with the cleaned filename as `title`, and the grandparent directory parsed as `parent_title` / `parent_year`.

**Pipeline flow for extras:**

1. **ParseFileName** passes the configured `extras_dirs` to the parser. When `type: :extra`, it sets `search_title` to `parent_title` and `parsed_year` to `parent_year`, so SearchTmdb searches for the parent movie (not the extra itself).
2. **SearchTmdb** routes `:extra` to the `:movie` search path — extras share the parent movie's TMDB match.
3. **FetchMetadata / EntityResolver** — for a new entity, creates the parent movie Entity (without setting `content_url` to the extra's file path) and then creates an `Extra` record linking the bonus feature to the entity. For an existing entity, only creates the `Extra` record.
4. **DownloadImages** downloads artwork for the parent movie entity only — extras have no separate artwork.
5. **Serializer** outputs extras as `hasPart` containing `@type: "VideoObject"` entries within the parent Movie entity.

**Key invariant:** The parent movie's `content_url` is never set to the extra's file path. Only standalone movie files set `content_url` on the Entity. Extras get their own `content_url` in the `Extra` record.

---

## Review Approval Flow

Files that reach `:pending_review` (low-confidence TMDB match or zero results) are surfaced in the `/review` admin UI. The reviewer can:

1. **Approve** — Accepts the current TMDB match. Triggers the same `:fetch_metadata` → `:download_images` pipeline steps as auto-approved files. Runs asynchronously via `Task.Supervisor`.
2. **Search** — Opens an inline TMDB search panel. The reviewer searches manually, selects a result (which sets `tmdb_id`, `match_title`, `match_year`, `match_poster_path`, `confidence_score: 1.0`), then approves.
3. **Dismiss** — Rejects the file, transitioning it to `:dismissed` (terminal state). The file is excluded from future processing.

### Review Ash Actions

| Action | Type | Behavior |
|--------|------|----------|
| `:approve` | update | Validates state is `:pending_review`, transitions to `:approved` |
| `:dismiss` | update | Validates state is `:pending_review`, transitions to `:dismissed` |
| `:set_tmdb_match` | update | Accepts `tmdb_id`, `match_title`, `match_year`, `match_poster_path`, `confidence_score`. Validates state is `:pending_review`. Does not change state — approve separately. |
| `:update_state` | update | Generic state setter for admin tools and test setup |
| `:pending_review_files` | read | Returns all files in `:pending_review` state, sorted by `inserted_at` ascending |

### Match Metadata Fields

The WatchedFile stores match metadata from the TMDB search result for display in the review UI:

| Attribute | Type | Purpose |
|-----------|------|---------|
| `match_title` | string | TMDB result title (movie title or TV series name) |
| `match_year` | string | Release year extracted from TMDB date field |
| `match_poster_path` | string | TMDB poster path fragment, rendered as CDN URL for thumbnail display |

These fields are set automatically during the `:search` step and can be overridden via `:set_tmdb_match` during manual review.

---

## Future Stages

- **Dynamic directory management** — Add/remove watch directories at runtime via the admin UI without restart
- **Subtitle files** — Currently ignored (`.srt`/`.ass`); future extension
- **Re-scrape** — Trigger fresh TMDB fetch for an existing entity from the admin UI
- **In-progress torrent detection** — File size stability polling is a pragmatic heuristic; could be replaced with watching for `.part` file removal
- **TVDB/other sources** — TMDB only for now; TVDB support is a future extension
