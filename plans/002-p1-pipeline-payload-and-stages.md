# 002-P1 — Pipeline Payload and Stage Functions

> **Status: Complete.** All 6 modules created, 34 tests passing, `mix precommit` clean.

## Context

Plan 002 redesigns the pipeline from Ash-change-driven side effects to standalone stage functions
that carry state in an in-memory Payload struct. Phase 1 is purely additive — new modules alongside
existing ones. Nothing is deleted or rewired. The existing pipeline continues to work unchanged.

## Deliverables

Six new modules and five new test files:

| Module | Test | async |
|--------|------|-------|
| `Pipeline.Payload` | (no test — data struct) | — |
| `Pipeline.Stages.Parse` | `test/media_manager/pipeline/stages/parse_test.exs` | yes |
| `Pipeline.Stages.Search` | `test/media_manager/pipeline/stages/search_test.exs` | yes |
| `Pipeline.Stages.FetchMetadata` | `test/media_manager/pipeline/stages/fetch_metadata_test.exs` | yes |
| `Pipeline.Stages.DownloadImages` | `test/media_manager/pipeline/stages/download_images_test.exs` | yes |
| `Pipeline.Stages.Ingest` | `test/media_manager/pipeline/stages/ingest_test.exs` | no (DataCase) |

## Stage Function Convention

Every stage is a module with a `run/1` function:

```elixir
@spec run(Payload.t()) :: {:ok, Payload.t()} | {:needs_review, Payload.t()} | {:error, term()}
```

- `{:ok, payload}` — success, continue to next stage
- `{:needs_review, payload}` — low confidence match, stop pipeline for this file (Search only)
- `{:error, reason}` — failure, fail the Broadway message

The pipeline's future `handle_message/3` will chain stages with `with`:

```elixir
with {:ok, p} <- Parse.run(p),
     {:ok, p} <- Search.run(p),
     {:ok, p} <- FetchMetadata.run(p),
     {:ok, p} <- DownloadImages.run(p),
     {:ok, p} <- Ingest.run(p) do
  {:ok, p}
end
```

`:needs_review` naturally short-circuits the `with` chain since it doesn't match `{:ok, _}`.

---

## 1. Pipeline.Payload

**File:** `lib/media_manager/pipeline/payload.ex`

```elixir
defmodule MediaManager.Pipeline.Payload do
  @type t :: %__MODULE__{}

  defstruct [
    # Input
    :file_path,
    :watch_directory,
    :entry_point,        # :file_detected | :review_resolved

    # Parse stage output
    :parsed,             # %Parser.Result{}

    # Search stage output
    :tmdb_id,            # integer
    :tmdb_type,          # :movie | :tv
    :confidence,         # float
    :match_title,        # string
    :match_year,         # integer | nil
    :match_poster_path,  # string | nil
    :candidates,         # list of scored candidates (for review)

    # FetchMetadata stage output
    :metadata,           # structured map (see below)

    # DownloadImages stage output
    :staged_images,      # list of {role, owner_id, local_path} tuples

    # Ingest stage output
    :entity_id,          # string (UUID)
    :ingest_status       # :new | :new_child | :existing
  ]
end
```

### Metadata structure

The `metadata` field is assembled by FetchMetadata using TMDB.Mapper. Shape:

```elixir
%{
  entity_type: :movie | :tv_series | :movie_series,
  entity_attrs: %{name: ..., description: ..., ...},
  images: [%{role: "poster", url: "...", extension: "jpg"}, ...],
  identifiers: [%{property_id: "tmdb", value: "550"}],
  collection: %{attrs: ..., images: ..., identifiers: ...} | nil,
  seasons: [%{attrs: ..., episodes: [%{attrs: ..., images: [...]}]}] | nil
}
```

---

## 2. Stages.Parse

**File:** `lib/media_manager/pipeline/stages/parse.ex`

Ports logic from `WatchedFile.Changes.ParseFileName`.

- Reads `extras_dirs` from Config
- Calls `Parser.parse(payload.file_path, extras_dirs: extras_dirs)`
- Sets `payload.parsed` to the `%Parser.Result{}`
- Returns `{:ok, payload}`
- For extras: the search title/year override is handled by the Search stage reading
  `parsed.parent_title`/`parsed.parent_year` when `parsed.type == :extra`

**Reuses:** `MediaManager.Parser.parse/2`, `MediaManager.Config.get/1`

**Tests:** Build Payload with `file_path`, call `Parse.run/1`, assert `parsed` fields match.
No DB, no HTTP. `async: true`.

---

## 3. Stages.Search

**File:** `lib/media_manager/pipeline/stages/search.ex`

Ports logic from `WatchedFile.Changes.SearchTmdb`. Key differences:
- Reads from `payload.parsed` instead of Ash changeset attributes
- For extras: uses `parsed.parent_title`/`parsed.parent_year` as search title/year
- Returns `{:ok, payload}` with match data when confidence >= threshold
- Returns `{:needs_review, payload}` with candidates when confidence < threshold or no results
- Returns `{:error, reason}` on TMDB API failure
- Populates `candidates` list on the payload for all cases

**Reuses (not duplicated):**
- `TMDB.Client.search_movie/2`, `TMDB.Client.search_tv/2`
- `TMDB.Confidence.score/6`, `TMDB.Confidence.threshold/0`
- `DateUtil.extract_year/1`

**Tests:** TMDB stubs via `TmdbStubs.setup_tmdb_client()`. Cases:
- Movie match above threshold → `{:ok, payload}` with tmdb_id, confidence
- TV match above threshold → `{:ok, payload}`
- Unknown type searches both, picks best → `{:ok, payload}`
- Low confidence → `{:needs_review, payload}` with candidates
- No results → `{:needs_review, payload}`
- TMDB error → `{:error, reason}`
- Extra type routes to movie/tv based on season_number
- No parsed title → `{:error, :no_title}`

---

## 4. Stages.FetchMetadata

**File:** `lib/media_manager/pipeline/stages/fetch_metadata.ex`

Extracts the TMDB-fetching and mapping logic currently inside `EntityResolver`.
Calls TMDB for full details and assembles the `metadata` map using `TMDB.Mapper`.

**Logic by type:**

**Movie:**
1. `Client.get_movie(tmdb_id)` → detail
2. If `belongs_to_collection` → `Client.get_collection(collection_id)`
3. Use `Mapper.movie_attrs/3` or `Mapper.child_movie_attrs/5` + `Mapper.movie_series_attrs/2`
4. Build image list from poster_path, backdrop_path, logo

**TV:**
1. `Client.get_tv(tmdb_id)` → detail
2. `Client.get_season(tmdb_id, season_number)` → season detail (only for the file's season)
3. Use `Mapper.tv_attrs/2`, `Mapper.season_attrs/2`, `Mapper.episode_attrs/4`
4. Build image/episode image lists

**Extra:** Same routing as movie/tv depending on `tmdb_type`, plus records extra title.

**Reuses:**
- `TMDB.Client.get_movie/2`, `get_tv/2`, `get_collection/2`, `get_season/3`
- `TMDB.Mapper.*` functions for attribute mapping

**Tests:** TMDB stubs, assert metadata map shape for: standalone movie, movie in
collection, TV with season/episode. No DB. `async: true`.

---

## 5. Stages.DownloadImages

**File:** `lib/media_manager/pipeline/stages/download_images.ex`

Downloads images from `metadata.images` (and nested collection/season/episode images) to a
staging directory. Does NOT update any DB records.

- Staging dir: `{System.tmp_dir!()}/media_manager_staging/{unique_id}/`
- Downloads each image URL to `{staging_dir}/{role}.{ext}`
- Individual failures logged but don't fail the stage
- Returns `{:ok, payload}` with `staged_images` populated
- Uses `Req.get/1` for HTTP
- Injectable via app config `:image_downloader` for testing (uses `NoopImageDownloader`)

**Tests:** Mock HTTP, temp staging dir, assert file paths in `staged_images`. `async: true`.

---

## 6. Stages.Ingest (Phase 1 Bridge)

**File:** `lib/media_manager/pipeline/stages/ingest.ex`

Temporary bridge to the existing `EntityResolver`. Replaced by `Library.Ingress` in Phase 2.

- Calls `EntityResolver.resolve/3` with `payload.tmdb_id`, type from payload, and file context
- On success: sets `payload.entity_id` and `payload.ingest_status`
- On error: returns `{:error, reason}`
- NOTE: EntityResolver re-fetches TMDB data — acceptable for Phase 1 bridge

**Tests:** DataCase (needs DB). TMDB stubs. Create payload with tmdb_id/tmdb_type,
call `Ingest.run/1`, verify entity created.

---

## Implementation Order

1. `Pipeline.Payload` — the struct
2. `Stages.Parse` + test
3. `Stages.Search` + test
4. `Stages.FetchMetadata` + test
5. `Stages.DownloadImages` + test
6. `Stages.Ingest` + test

After each stage + test: `mix test` for that file.
After all stages: `mix precommit`.

## Files Created

```
lib/media_manager/pipeline/payload.ex
lib/media_manager/pipeline/stages/parse.ex
lib/media_manager/pipeline/stages/search.ex
lib/media_manager/pipeline/stages/fetch_metadata.ex
lib/media_manager/pipeline/stages/download_images.ex
lib/media_manager/pipeline/stages/ingest.ex
test/media_manager/pipeline/stages/parse_test.exs
test/media_manager/pipeline/stages/search_test.exs
test/media_manager/pipeline/stages/fetch_metadata_test.exs
test/media_manager/pipeline/stages/download_images_test.exs
test/media_manager/pipeline/stages/ingest_test.exs
```

## Files Modified

None. Phase 1 is purely additive.

## Verification

1. Each test file passes individually
2. Full test suite passes: `mix test`
3. `mix precommit` passes
4. Existing pipeline tests still pass unchanged
