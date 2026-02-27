# 002-P2 — Library Ingress

> **Status: Complete.** Ingress module created, Stages.Ingest updated, 19 tests passing, `mix precommit` clean (320 tests, 0 failures).

## Context

Phase 1 built standalone pipeline stage functions that produce a pre-assembled metadata map
(via FetchMetadata) and download images to a staging directory (via DownloadImages). The
Phase 1 Ingest bridge delegates to `EntityResolver`, which re-fetches TMDB data internally
— doubling the work.

Phase 2 replaces this bridge with `Library.Ingress`, a dedicated module that consumes the
pre-built metadata and staged images to create/update all library records without any TMDB
calls. This eliminates the double-fetch and cleanly separates the "gather data" stages
(Parse, Search, FetchMetadata, DownloadImages) from the "persist data" stage (Ingest).

## Deliverables

| Module | Action |
|--------|--------|
| `lib/media_manager/library/ingress.ex` | New — the Library's inbound API |
| `lib/media_manager/pipeline/stages/ingest.ex` | Modified — calls Ingress instead of EntityResolver |
| `test/media_manager/library/ingress_test.exs` | New — DataCase tests for all Ingress scenarios |
| `test/media_manager/pipeline/stages/ingest_test.exs` | Modified — update to match new Ingress call |

## Design

### Public API

```elixir
defmodule MediaManager.Library.Ingress do
  @spec ingest(Payload.t()) :: {:ok, Entity.t(), :new | :new_child | :existing} | {:error, term()}
  def ingest(payload)
end
```

Takes a `Payload` with `metadata` and `staged_images` populated. Returns the same
`{:ok, entity, status}` shape as EntityResolver so the Stages.Ingest wrapper can set
`entity_id` and `ingest_status` on the payload identically to today.

### Internal Flow

```
ingest(payload)
  │
  ├── find_existing_entity(metadata.identifier)
  │     │
  │     ├── found → link_to_existing(entity, metadata, staged_images)
  │     │             ├── TV: ensure season + episode from metadata.season
  │     │             ├── MovieSeries: ensure child movie from metadata.child_movie
  │     │             ├── Extra: create extra from metadata.extra
  │     │             └── Movie: set content_url if nil
  │     │
  │     └── not found → create_new(metadata, staged_images)
  │                       ├── Create Entity from metadata.entity_attrs
  │                       ├── Create Identifier (with race-loss recovery)
  │                       ├── Create Image records from metadata.images
  │                       ├── Move staged entity images to permanent storage
  │                       ├── TV: create Season + Episode + episode images
  │                       ├── Collection: create child Movie + movie images
  │                       └── Extra: create Extra record
```

### Key Differences from EntityResolver

1. **No TMDB calls.** All data comes from `metadata` map (pre-built by FetchMetadata).
2. **Staged images.** Moves files from staging dir to permanent storage instead of
   downloading from TMDB CDN. Creates Image records AND sets content_url in one pass.
3. **Cleaner separation.** EntityResolver mixes TMDB fetching with entity creation.
   Ingress only does persistence.

### Image Handling

FetchMetadata populates `metadata.images` (and nested child_movie/episode images) with
`%{role, url, extension}` maps. DownloadImages downloads those to staging and records
`staged_images` as `%{role, owner, local_path}` maps.

The Ingress:
1. Creates Image records for ALL images in metadata (url, role, extension, owner_id).
2. For each staged_image: moves the file from staging to permanent storage
   (`{images_dir}/{owner_id}/{role}.{ext}`) and sets `content_url` on the Image record.
3. Images that failed to download (not in staged_images) get Image records with
   `content_url: nil` — they can be retried later.

Matching staged images to owners:
- `owner: "entity"` + role → Image with `entity_id`
- `owner: "child_movie"` + role → Image with `movie_id`
- `owner: "episode"` + role → Image with `episode_id`

### Race-Loss Recovery

Same pattern as EntityResolver: `Identifier.find_or_create` is an upsert. If the returned
identifier's `entity_id` differs from the entity we just created, another process won the
race. We destroy our orphan entity and link to the winner instead.

### What Ingress Does NOT Do

- **No WatchedFile creation.** In the current architecture, WatchedFile records are created
  by the Watcher (Phase 5 changes that). The Stages.Ingest wrapper sets `entity_id` on the
  payload — the pipeline handles WatchedFile linking.
- **No PubSub broadcasts.** The pipeline batcher handles broadcasts (existing behavior).
  The Ingress is a pure persistence operation.

---

## Implementation Plan

### 1. Create `Library.Ingress`

**File:** `lib/media_manager/library/ingress.ex`

Functions to implement (ported from EntityResolver, adapted for metadata maps):

**Top-level:**
- `ingest/1` — entry point, dispatches to find-or-create flow
- `find_existing_entity/1` — queries Identifier by metadata.identifier

**Create new:**
- `create_entity/2` — creates Entity from metadata.entity_attrs
- `create_identifier_with_race_retry/2` — same race-loss pattern as EntityResolver
- `create_images/3` — bulk creates Image records, moves staged files
- `create_season_and_episode/3` — from metadata.season (no TMDB calls)
- `create_child_movie/3` — from metadata.child_movie (no TMDB calls)
- `create_extra/2` — from metadata.extra

**Link to existing:**
- `link_to_existing/4` — dispatches by entity type
- `ensure_episode/3` — finds or creates season + episode from metadata.season
- `ensure_child_movie/3` — finds or creates child movie from metadata.child_movie

**Image helpers:**
- `move_staged_images/3` — moves files from staging to permanent, updates content_url
- `find_staged_image/3` — matches a staged image by owner + role

**Reuses from existing codebase (not duplicated):**
- `Ash.create(Entity, attrs, action: :create_from_tmdb)`
- `Ash.create(Identifier, attrs, action: :find_or_create)`
- `Ash.create(Season, attrs, action: :find_or_create)`
- `Ash.create(Episode, attrs, action: :find_or_create)`
- `Ash.create(Movie, attrs, action: :find_or_create)`
- `Ash.create(Extra, attrs, action: :find_or_create)`
- `Ash.bulk_create(image_attrs, Image, :find_or_create, return_errors?: true)`
- `Ash.Query.for_read(Identifier, :find_by_tmdb_id, ...)`
- `Ash.Query.for_read(Identifier, :find_by_tmdb_collection, ...)`

### 2. Update `Stages.Ingest`

**File:** `lib/media_manager/pipeline/stages/ingest.ex`

Change from:
```elixir
EntityResolver.resolve(tmdb_id, parsed_type, file_context)
```

To:
```elixir
Library.Ingress.ingest(payload)
```

The wrapper still sets `entity_id` and `ingest_status` on the payload.

### 3. Tests

**File:** `test/media_manager/library/ingress_test.exs`

Uses `DataCase` (needs DB). No TMDB stubs needed — the Ingress doesn't call TMDB.
Constructs metadata maps and staged image files directly.

**Test cases (ported from entity_resolver_test.exs):**
1. Standalone movie — creates entity, identifier, images
2. Movie with staged images — creates entity, moves images to permanent storage
3. Movie in collection — creates movie_series + child movie + identifiers + images
4. TV series — creates entity, season, episode, episode images
5. Existing entity reuse — finds by identifier, returns :existing
6. Existing TV adds new episode — ensures season + episode
7. Existing collection adds child movie
8. Extra without season — creates entity + extra
9. Extra with season — creates entity + season + extra
10. Race-loss recovery — second concurrent ingest reuses winner
11. Error handling — invalid metadata returns error

**Setup helper:** Build metadata maps and staged image files in a temp dir.

### 4. Update `Stages.Ingest` test

Simplify test — no TMDB stubs needed since Ingress doesn't call TMDB. Build payload
with metadata + staged_images directly.

---

## Files Created

```
lib/media_manager/library/ingress.ex
test/media_manager/library/ingress_test.exs
```

## Files Modified

```
lib/media_manager/pipeline/stages/ingest.ex      — call Ingress instead of EntityResolver
test/media_manager/pipeline/stages/ingest_test.exs — update for new Ingress call
```

## Key Source Files (Reference)

- `lib/media_manager/library/entity_resolver.ex` — logic being ported
- `lib/media_manager/pipeline/stages/fetch_metadata.ex` — metadata map structure
- `lib/media_manager/pipeline/stages/download_images.ex` — staged_images structure
- `lib/media_manager/pipeline/image_downloader.ex` — permanent image storage pattern
- `lib/media_manager/library/entity.ex` — Entity resource actions
- `lib/media_manager/library/identifier.ex` — Identifier find_or_create + find_by_tmdb_id
- `lib/media_manager/library/image.ex` — Image find_or_create actions
- `lib/media_manager/library/season.ex` — Season find_or_create
- `lib/media_manager/library/episode.ex` — Episode find_or_create
- `lib/media_manager/library/movie.ex` — Movie find_or_create
- `lib/media_manager/library/extra.ex` — Extra find_or_create

## Verification

1. `mix test test/media_manager/library/ingress_test.exs` — all Ingress tests pass
2. `mix test test/media_manager/pipeline/stages/ingest_test.exs` — updated Ingest stage tests pass
3. `mix test` — full suite passes (existing EntityResolver tests still pass unchanged)
4. `mix precommit` — clean
