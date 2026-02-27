# 002 — Context Boundary Redesign

> **Status: In Progress.** Phase 1 ✓, Phase 2 ✓, Phase 3 ✓, Phase 4 ✓, Phase 5 ✓. Phase 6 next.

## Problem Statement

The current architecture couples pipeline orchestration state and behavior into
core domain entities. `WatchedFile` is a god object carrying both domain data
(file path, entity link) and pipeline-intermediate state (TMDB match data,
confidence scores, processing stage). Pipeline steps are implemented as Ash
change modules that trigger external integrations (TMDB API calls, image
downloads) as side effects of resource state changes.

This creates several problems:

- **Blast radius.** Any change to a resource used by the pipeline affects every
  other feature that touches that resource (LiveViews, channels, admin screens).
- **Testing complexity.** Testing a pipeline step requires setting up an Ash
  resource with database state, even when the step's logic is fundamentally
  about calling an API and transforming data.
- **Hidden coupling.** The pipeline's behavior is encoded in Ash change modules
  scattered across `lib/media_manager/library/watched_file/changes/`. Reading
  the pipeline requires jumping between the Broadway module, the change modules,
  and the resource definition.
- **God object.** `WatchedFile` carries fields for every pipeline stage
  (`tmdb_results`, `tmdb_id`, `tmdb_type`, `confidence`, `state`, etc.) that
  are only meaningful during pipeline processing and irrelevant to the file's
  role as a library record.

## Design Values

These values apply to all future development, not just this refactor:

1. **Low coupling between features.** Each feature/context owns its own data and
   behavior. Modifying one feature should not require analyzing the blast radius
   on unrelated features.

2. **Contexts communicate through PubSub boundaries.** Cross-context interaction
   happens via events, not shared resources or direct function calls into
   another context's internals.

3. **Ash changes are a yellow flag.** Ash changes are appropriate for data
   validation and transformation intrinsic to a resource (normalizing a name,
   computing a derived field). They must NOT orchestrate external integrations,
   call APIs, download files, or cross context boundaries. Every Ash change
   should be reviewed with this lens.

4. **The pipeline is a mediator, not a side effect.** The pipeline actively
   orchestrates — it calls services, gathers data, and hands results to the
   library. Domain resources do not trigger pipeline behavior through their own
   state changes.

5. **Features are decoupled even at the cost of "redundant" data.** It is
   acceptable for multiple contexts to store overlapping data if it preserves
   boundary isolation.

## Context Map

Seven bounded contexts. Data flows primarily in one direction:
Watching → Pipeline → Library.

### 1. Config

- **Responsibility:** Reads TOML configuration, provides settings to all other
  contexts.
- **Persistence:** TOML files + `Setting` Ash resource.
- **Boundary:** Shared infrastructure. Other contexts read from Config but never
  write to it.
- **Changes from current:** None. Already a clean boundary.

### 2. Parser

- **Responsibility:** Pure function context. Transforms a file path into a
  structured `%Parser.Result{}` struct.
- **Persistence:** None. Stateless, no side effects.
- **Public API:** `Parser.parse(path, opts)` → `%Parser.Result{}`.
- **Consumers:** Pipeline (as its first stage), Review (for re-parsing during
  manual search).
- **Changes from current:** None. Already a clean boundary.

### 3. TMDB

- **Responsibility:** API client context for interacting with the TMDB service.
  Search movies/TV, get details, get season data, get collection data.
- **Persistence:** None. Stateless HTTP client.
- **Rate limiting:** Owned internally via the Req client.
- **Public API:** The existing `TMDB.Client` module and its functions.
- **Consumers:** Pipeline (for auto-matching), Review (for human-driven search).
- **Changes from current:** None. Already a clean boundary. The key change is
  that the pipeline calls TMDB directly instead of through Ash changes.

### 4. File Watching

- **Responsibility:** Observes the filesystem for video file changes. Detects
  new files (via inotify) and directory scans.
- **Persistence:** None. Stateless. No database records.
- **Output:** Emits `"file detected"` events via PubSub with the file path and
  watch directory.
- **Note:** Any trigger that produces a "file detected" event (inotify,
  directory scan, manual trigger) enters the same PubSub channel. The pipeline
  does not know or care about the source.
- **Changes from current:** The watcher currently creates `WatchedFile` records
  in the database. After this redesign, it only emits PubSub events. It does
  not write to the database at all.

### 5. Pipeline

- **Responsibility:** Ephemeral multi-stage processor. Consumes file events,
  enriches them into fully-formed entity data, and hands results to the Library
  ingress.
- **Persistence:** None. State lives in Broadway message payloads between
  stages. Does not survive restarts. Incomplete jobs are simply lost — the
  watcher will re-detect files on next scan.
- **Technology:** Broadway with a PubSub-consuming producer.
- **Changes from current:** This is the biggest change. The pipeline currently
  works by updating `WatchedFile` records through Ash actions with change
  modules that do the real work. After this redesign, the pipeline is a pure
  Broadway pipeline where each stage is a function call (Parser, TMDB, Library
  ingress) — no Ash resources involved in the processing path.

#### Pipeline Stages

Sequential per message, state carried in a payload struct:

1. **Parse** — calls Parser context, gets `%Parser.Result{}`.
2. **Search TMDB** — calls TMDB context, scores matches against parsed data.
   - High confidence: continue to next stage with TMDB ID in payload.
   - Low confidence: emit `"needs review"` event to PubSub with all accumulated
     data (parsed info, TMDB candidates, scores). Pipeline job for this file
     ends here.
3. **Fetch metadata** — calls TMDB context for full details
   (movie/TV/season/collection). Assembles complete entity data structure in
   payload.
4. **Download images** — downloads image files from TMDB CDN to a **temporary
   staging directory** (not the library's permanent storage). File paths added
   to payload.
5. **Ingest** — calls Library ingress API with the fully-enriched payload.
   Library handles persistence, deduplication, and moving staged images to
   permanent storage.

#### Pipeline Entry Points

Two entry points into the pipeline:

1. **From File Watching** — raw file path, full pipeline run (all 5 stages).
2. **From Review resolution** — file path + confirmed TMDB ID, skips search
   stage (TMDB ID is already resolved by the human). Enters at stage 3 (fetch
   metadata).

#### Pipeline Payload

The pipeline carries all intermediate state in a struct (not in the database).
Rough shape:

```elixir
defmodule MediaManager.Pipeline.Payload do
  defstruct [
    :file_path,
    :watch_directory,
    :parsed,           # %Parser.Result{}
    :tmdb_id,          # integer
    :tmdb_type,        # :movie | :tv
    :confidence,       # float
    :metadata,         # map — fully assembled entity data
    :staged_images,    # list of {role, local_path} tuples
    :entry_point       # :file_detected | :review_resolved
  ]
end
```

### 6. Review

- **Responsibility:** Manages low-confidence TMDB matches that require human
  decision.
- **Persistence:** Own Ash domain with own Ash resources. Stores file path,
  parsed data, TMDB search candidates, confidence scores, poster references —
  everything the human needs to make a decision.
- **UI:** Own LiveView (the review screen). Only integrates with the Review
  context.
- **Changes from current:** Currently, low-confidence matches are tracked via
  `WatchedFile` state (`:needs_review`). After this redesign, the Review
  context is a standalone bounded context with its own persistence.

#### Review Capabilities

- Presents TMDB candidates to the human.
- Human can approve a candidate, search for alternatives (using TMDB and Parser
  contexts), or dismiss.
- On approval: emits `"review resolved"` event via PubSub with file path +
  confirmed TMDB ID. Pipeline consumes this and resumes processing.
- On dismissal: no pipeline event. Review record is retained until cleanup.

#### Review Lifecycle

- **Created:** When the pipeline emits `"needs review"`.
- **Resolved:** When the human approves a candidate. Emits PubSub event.
- **Cleaned up:** When the Library broadcasts that the corresponding entity was
  successfully ingested (closing the feedback loop). Dismissed reviews follow
  their own cleanup policy.

#### Review Ash Domain (Sketch)

```elixir
defmodule MediaManager.Review do
  use Ash.Domain
  # resources: [MediaManager.Review.PendingFile]
end

defmodule MediaManager.Review.PendingFile do
  use Ash.Resource
  # Attributes:
  #   file_path       — string, the video file path
  #   watch_directory — string, the watch directory it came from
  #   parsed_title    — string, from Parser
  #   parsed_year     — integer, from Parser
  #   parsed_type     — atom, from Parser
  #   candidates      — :map (list of TMDB candidates with scores)
  #   status          — :pending | :approved | :dismissed
  #   approved_tmdb_id   — integer, set on approval
  #   approved_tmdb_type — atom, set on approval
  #
  # Timestamps
end
```

### 7. Library

- **Responsibility:** The domain catalog. Source of truth for all media entities
  ready for the media center.
- **Persistence:** Ash domain with resources: Entity, Image, Identifier, Season,
  Episode, WatchProgress.
- **Changes from current:** Several significant changes:

#### WatchedFile Simplification

`WatchedFile` becomes a thin domain object within the Library — records that a
file at a given path is linked to a given entity. All pipeline state fields are
removed:

**Fields removed from WatchedFile:**
- `tmdb_results` — pipeline intermediate state
- `tmdb_id` — pipeline intermediate state (Library uses Identifier records)
- `tmdb_type` — pipeline intermediate state
- `confidence` — pipeline intermediate state
- `state` — pipeline state machine (the entire state column and state machine)

**Fields retained on WatchedFile:**
- `id` — primary key
- `path` — the file path
- `entity_id` — the linked entity (relationship)
- `media_type` — audio/video/etc.
- Timestamps

#### Extras as First-Class Entities

Extras (bonus features, featurettes, behind-the-scenes, etc.) become entities in
their own right (`type: :video_object`) that *may* have a relationship to a
parent entity but don't require one. A user may have extras without owning the
parent film, and that's valid.

The current `Extra` resource (with required `entity_id`) is replaced by entities
with optional parent relationships.

#### Library Ingress

A dedicated subcontext/module within the Library that receives enriched data from
the Pipeline and translates it into Ash resources. This replaces what
`EntityResolver` does today, but with a cleaner interface.

The ingress handles:
- Entity find-or-create (movies, TV series, collections, extras as first-class
  entities).
- Identifier management (TMDB ID deduplication, race-loss recovery).
- Image record creation and moving staged image files to permanent storage.
- TV hierarchy creation (seasons, episodes).
- Extra → parent entity linking (optional, not required).
- WatchedFile record creation (linking file path to entity).
- All consistency guarantees — the ingress is the aggregate boundary.

**Ingress public API (sketch):**

```elixir
defmodule MediaManager.Library.Ingress do
  @doc """
  Accepts a fully-enriched pipeline payload and creates/updates all
  necessary library records. Returns {:ok, entity} or {:error, reason}.

  This is the only entry point from the pipeline into the library.
  """
  def ingest(payload) do
    # 1. Find or create entity by TMDB identifier
    # 2. Update entity metadata
    # 3. Move staged images to permanent storage, create Image records
    # 4. Create/update seasons and episodes (for TV)
    # 5. Create WatchedFile record linking path to entity
    # 6. Broadcast entity changed
  end
end
```

#### Library Broadcasts

The Library itself emits PubSub events whenever entities are created or updated,
regardless of what triggered the change. The pipeline does not broadcast — it
hands data to the library and walks away.

This is largely how it works today — the change is that the pipeline no longer
triggers broadcasts through Ash change side effects. The Library ingress
explicitly broadcasts after successful persistence.

## Event Flow

```
[Config provides settings to all contexts]

File Watching ──"file detected"──→ PubSub ──→ Pipeline Producer
                                                    │
                                              Parse (Parser ctx)
                                                    │
                                          Search TMDB (TMDB ctx)
                                             │              │
                                        high confidence   low confidence
                                             │              │
                                    Fetch metadata    "needs review"──→ PubSub ──→ Review
                                             │                                       │
                                    Download images                          Human decides
                                     (to staging dir)                                │
                                             │                          "review resolved"──→ PubSub
                                             │                                               │
                                      Library Ingress ←──────────────────────────────────────┘
                                             │
                                   Create/update entities
                                   Move images to permanent storage
                                             │
                                   "entity changed"──→ PubSub ──→ Library Channel → UI
                                                           │
                                                           └──→ Review (cleanup)
```

## PubSub Topics and Messages

| Topic | Message | Producer | Consumer(s) |
|-------|---------|----------|-------------|
| `"pipeline:input"` | `{:file_detected, %{path: String.t(), watch_dir: String.t()}}` | File Watching | Pipeline |
| `"pipeline:input"` | `{:review_resolved, %{path: String.t(), tmdb_id: integer(), tmdb_type: atom()}}` | Review | Pipeline |
| `"pipeline:review"` | `{:needs_review, %{path: String.t(), parsed: Parser.Result.t(), candidates: list()}}` | Pipeline | Review |
| `"library:updates"` | `{:entities_changed, entity_ids}` | Library | Channel, Review |

## What Gets Deleted

The following modules/files are removed or substantially hollowed out:

| Current module | Disposition |
|----------------|------------|
| `lib/media_manager/library/watched_file/changes/search_tmdb.ex` | **Deleted.** Logic moves to pipeline stage function. |
| `lib/media_manager/library/watched_file/changes/fetch_metadata.ex` | **Deleted.** Logic moves to pipeline stage function. |
| `lib/media_manager/library/watched_file/changes/download_images.ex` | **Deleted.** Logic moves to pipeline stage function. |
| `lib/media_manager/library/watched_file/changes/serialize.ex` | **Deleted.** Serialization is called by Library ingress or channel, not as an Ash change. |
| `lib/media_manager/library/watched_file/changes/detect.ex` | **Deleted** if it only handled pipeline state transitions. |
| `lib/media_manager/library/entity_resolver.ex` | **Replaced** by `Library.Ingress`. Core find-or-create logic is preserved but moved. |
| `lib/media_manager/pipeline/producer.ex` | **Rewritten.** No longer claims WatchedFile records from DB. Consumes PubSub events instead. |
| `lib/media_manager/pipeline.ex` | **Rewritten.** Broadway stages call context functions directly instead of Ash update actions. |

## What Gets Created

| New module | Purpose |
|------------|---------|
| `lib/media_manager/pipeline/payload.ex` | Struct carrying all intermediate pipeline state. |
| `lib/media_manager/pipeline/stages/parse.ex` | Stage 1: calls Parser, returns enriched payload. |
| `lib/media_manager/pipeline/stages/search.ex` | Stage 2: calls TMDB search, scores, decides confidence. |
| `lib/media_manager/pipeline/stages/fetch_metadata.ex` | Stage 3: calls TMDB details, assembles entity data. |
| `lib/media_manager/pipeline/stages/download_images.ex` | Stage 4: downloads images to staging directory. |
| `lib/media_manager/pipeline/stages/ingest.ex` | Stage 5: calls Library ingress. |
| `lib/media_manager/library/ingress.ex` | Library's inbound API from the pipeline. Handles entity creation, image moves, WatchedFile linking. |
| `lib/media_manager/review.ex` | Review Ash domain. |
| `lib/media_manager/review/pending_file.ex` | Review Ash resource for files needing human decision. |
| `lib/media_manager_web/live/review_live.ex` | Review LiveView (replaces current review screen's data source). |

## What Gets Modified

| Existing module | Changes |
|-----------------|---------|
| `WatchedFile` resource | Remove all pipeline state fields (`tmdb_results`, `tmdb_id`, `tmdb_type`, `confidence`, `state` and state machine). Keep `path`, `entity_id`, `media_type`, timestamps. Remove all pipeline-related actions and changes. |
| `Watcher` / `Watcher.Supervisor` | Stop creating `WatchedFile` records. Emit PubSub events instead. |
| `Pipeline` (Broadway) | Rewrite to consume PubSub events. Stages are function calls, not Ash actions. |
| `Pipeline.Producer` | Rewrite to consume from PubSub instead of claiming DB records. |
| `Pipeline.ImageDownloader` | Download to staging directory instead of permanent storage. Library ingress moves files. |
| `Extra` resource | Replace with entities having optional parent relationship. |
| `Serializer` | May need minor adjustments for extras-as-entities. |
| Test files | Pipeline tests rewritten to test the new stage functions. Factory updated for new structures. |

## Migration Strategy

This redesign touches the database schema (removing fields from WatchedFile,
adding the Review domain, changing Extras). The migration must be planned
carefully since SQLite has limited ALTER TABLE support.

### Recommended Implementation Order

Each phase should be a self-contained set of changes that passes `mix precommit`
before moving to the next.

#### Phase 1: Create Pipeline Payload and Stage Functions ✓

**Complete.** See `plans/002-p1-pipeline-payload-and-stages.md` for details.

All 6 stage modules created with 34 tests. Purely additive — no existing
code modified.

#### Phase 2: Create Library Ingress ✓

Build the Library's inbound API as a new module.

1. ✓ Create `Library.Ingress` module with `ingest/1` function.
2. ✓ Port the core logic from `EntityResolver` into the ingress (find-or-create,
   identifier management, image storage, TV hierarchy).
3. ✓ The ingress accepts a `Pipeline.Payload` and returns `{:ok, entity, status}`.
4. ✓ Update `Pipeline.Stages.Ingest` to call `Library.Ingress` instead of
   `EntityResolver`.
5. ✓ Write tests for the ingress (14 tests) and updated Ingest stage (5 tests).

#### Phase 3: Create Review Context ✓

Built the Review bounded context with its own Ash domain and resource.

1. ✓ Created `Review` Ash domain and `Review.PendingFile` resource with actions:
   `:create`, `:find_or_create` (upsert), `:approve`, `:dismiss`,
   `:set_tmdb_match`, `:pending` (read).
2. ✓ Generated migration for `review_pending_files` table.
3. ✓ Created `Review.Intake` module — maps `Pipeline.Payload` fields to
   `PendingFile` attributes (the pipeline's outbound API to Review).
4. ✓ Added `Review` helper functions in `review.ex` for the LiveView
   (`fetch_pending_files`, `approve_and_process`, `dismiss`, `set_tmdb_match`,
   `search_tmdb`).
5. ✓ ReviewLive already existed — data source switch deferred to Phase 4.
6. ✓ Tests: 13 tests for PendingFile resource and Intake module.

**Note:** PubSub-based event flow (pipeline emits "needs review", Review
subscribes) was deferred. Instead, the pipeline calls
`Intake.create_from_payload/1` directly. PubSub decoupling is a future
phase.

#### Phase 4: Rewire Pipeline + Update Review Flow ✓

Switched the running system from WatchedFile Ash change modules to
Payload-based stage functions. The new architecture is now live.

1. ✓ Rewrote `Pipeline.process_file/1` — builds a `Payload` from the
   claimed `WatchedFile` and runs `Parse → Search → FetchMetadata →
   DownloadImages → Ingest` stage functions.
2. ✓ Three outcome handlers: `mark_complete/2` (WatchedFile → `:complete`
   with entity_id), `send_to_review/2` (creates PendingFile via
   `Intake.create_from_payload/1`, WatchedFile → `:pending_review`),
   `mark_error/2` (WatchedFile → `:error` with error_message).
3. ✓ Updated `Review` module — switched from WatchedFile to PendingFile:
   `fetch_pending_files/0` reads PendingFile `:pending`, `approve_and_process/1`
   builds Payload and runs post-search stages (FetchMetadata → DownloadImages →
   Ingest), then destroys PendingFile. Removed `retry/1`.
4. ✓ Updated `ReviewLive` — field renames (`watch_dir` → `watch_directory`,
   `confidence_score` → `confidence`), string `parsed_type` handling, removed
   Retry button.
5. ✓ Rewrote pipeline tests to use Payload + stage functions, added PendingFile
   assertion for low-confidence case.
6. ✓ Fixed `NoopImageDownloader` to support `download/2` (new staging
   downloader API) and added `:staging_image_downloader` config to `test.exs`.

**What was NOT done (deferred to Phase 6):**
- WatchedFile still carries all pipeline state fields (Phase 6 strips them).
- Old Ash change modules still exist (unused, Phase 6 deletes them).

#### Phase 5: Rewire File Watching + PubSub Producer ✓

Completed. Key changes:

1. **Payload**: Added `:pending_file_id` field for review-resolved cleanup.
2. **WatchedFile**: Added `:link_file` create action (upsert on file_path,
   sets `state: :complete` with `entity_id`). WatchedFile is now created at
   pipeline completion, not detection.
3. **Producer**: Complete rewrite — subscribes to `"pipeline:input"` PubSub topic,
   receives `{:file_detected, ...}` and `{:review_resolved, ...}` events,
   converts to Payloads, dispatches on demand. Pure `build_payload/2` tested.
4. **Pipeline**: `process_payload/1` routes by entry_point. `:file_detected` dedup
   checks WatchedFile, runs full pipeline. `:review_resolved` skips search,
   runs fetch → download → ingest. Completion creates WatchedFile via `:link_file`
   and destroys PendingFile if `pending_file_id` set.
5. **Watcher**: `detect_file/2` broadcasts PubSub event instead of creating
   WatchedFile. `scan_directory/1` reads existing WatchedFile file_paths (bulk
   query) to skip already-processed files.
6. **Review**: `approve_and_process/1` broadcasts `{:review_resolved, ...}` to
   `"pipeline:input"`. No more Task.Supervisor, stage function aliases, or
   inline pipeline execution.
7. **Dashboard**: `fetch_pipeline_stats/0` returns `%{complete: N, pending_review: M}`.
   `fetch_pending_review/0` reads PendingFile. `fetch_recent_errors/0` returns `[]`.
   LiveView simplified — removed progress bar, `@transient_states`, in_progress
   counting, pipeline cooldown timer.
8. **Factory**: Added `create_linked_file/1`, `create_pending_file/1`. Kept legacy
   helpers (`create_pending_review_file`, `create_approved_file`,
   `create_fetching_images_file`) for Ash change module tests. Removed
   `create_queued_file` (unused).

#### Phase 6: Clean Up WatchedFile + Delete Old Modules

1. Remove all pipeline state fields from `WatchedFile` resource definition
   (`tmdb_id`, `confidence_score`, `match_title`, `match_year`,
   `match_poster_path`, `parsed_type`, `parsed_title`, `season_number`,
   `episode_number`, `search_title`, `error_message`, `state` machine fields).
2. Remove all pipeline-related actions and changes from `WatchedFile`
   (`:search`, `:fetch_metadata`, `:download_images`, `:approve`, `:dismiss`,
   `:retry`, `:set_tmdb_match`, `:update_state`, `:pending_review_files`).
3. Generate Ash migration to drop the removed columns.
4. Delete the old Ash change modules (`search_tmdb.ex`, `fetch_metadata.ex`,
   `download_images.ex`, `serialize.ex`, `parse_file_name.ex`).
5. Delete `EntityResolver` (fully replaced by `Library.Ingress`).
6. Update all tests and factory helpers.

#### Phase 7: Extras as First-Class Entities

1. Remove the `Extra` resource.
2. Add optional `parent_entity_id` relationship to `Entity`.
3. Ensure extras are created as entities with `type: :video_object`.
4. Generate migration.
5. Update serializer, channel, and tests.

#### Phase 8: Documentation Updates

1. Update `CLAUDE.md` to codify design values and new architecture.
2. Update `PIPELINE.md` to document the new pipeline architecture.
3. Update `AGENTS.md` if needed.
4. Update the repository layout table in `CLAUDE.md`.

## Testing Strategy for the Redesign

- **Phase 1 tests** are pure function tests — each stage is tested with stub
  inputs and TMDB stubs. No database needed for stages 1-4. Stage 5 (ingest)
  needs `DataCase`.
- **Phase 2 tests** use `DataCase` — test the ingress against real DB.
- **Phase 3 tests** use `DataCase` for the Review resource and `ConnCase` for
  the LiveView.
- **Phase 4 tests** are integration tests — message flows through the full
  Broadway pipeline with TMDB stubs and a real DB.
- **Phase 5-6 tests** verify the wiring is correct and old code is gone.
- **Existing tests are never deleted.** They are migrated to test the new
  modules. Every scenario currently tested continues to be tested.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Large blast radius — many files change | Phased approach; each phase is self-contained and passes `mix precommit`. |
| Pipeline state lost on restart | Acceptable by design. Watcher re-detects files on next scan. Document this explicitly. |
| Race conditions during ingress | Library ingress is the single point of deduplication, same as current EntityResolver. Race-loss recovery logic is preserved. |
| SQLite migration complexity | Each schema change gets its own migration. Test migrations against a copy of production data before applying. |
| Review records accumulate | Cleanup subscriber listens for entity-changed events. Add a periodic cleanup for dismissed reviews. |

## Out of Scope

- File removal handling (watcher detecting deleted files, library cleanup).
- Detailed Ash resource attribute definitions for the Review domain (to be
  designed during Phase 3 implementation).
- Data migration from existing `WatchedFile` pipeline fields to new structures
  (existing pipeline data is ephemeral and can be re-derived).
- Performance optimization of the new pipeline (measure first, optimize later).
