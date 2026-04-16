# Track New Show — Design Spec

**Date:** 2026-04-06
**Status:** Draft

## Problem

The Upcoming page's "Scan Library" button bulk-discovers and auto-tracks everything at once. This gives users no control over what gets tracked and provides no way to track shows or movies that aren't already in the library. The TMDB production status (returning, ended, canceled) is fetched during pipeline processing but discarded — the Library has no record of whether a series is still active.

## Solution

Two-phase approach:

1. **Phase 1 — Auto-tracking infrastructure**: Store TMDB production status in the Library. When the pipeline adds a new active TV series, ReleaseTracking auto-tracks it via PubSub. No user action required.
2. **Phase 2 — Track New Show modal**: Replace "Scan Library" with a "Track New Show" button that opens a polished modal for manually tracking movies and shows not in the library, with a suggestions section for edge cases.

---

## Phase 1: Auto-Tracking Infrastructure

### 1.1 Library Status Fields

Add `status` field to `Library.TVSeries` and `Library.Movie` schemas.

**TVSeries status values** (from TMDB):
- `:returning` — currently airing, renewed
- `:ended` — concluded, no more episodes
- `:canceled` — canceled before natural conclusion
- `:in_production` — ordered but not yet aired
- `:planned` — announced but not in production

**Movie status values** (from TMDB):
- `:released`
- `:in_production`
- `:post_production`
- `:planned`
- `:rumored`
- `:canceled`

**Migration**: Add nullable `status` column to both `library_tv_series` and `library_movies`. Nullable because existing records won't have status until their next pipeline refresh.

### 1.2 Pipeline Updates

Update `TMDB.Mapper.tv_attrs/2` and `movie_attrs/2` to extract and include the `status` field from TMDB responses. The TMDB JSON already contains this data — it's just being discarded today.

The `ReleaseTracking.Extractor` module already has `extract_tv_status/1` and `extract_movie_status/1` functions that parse the TMDB status strings. Reuse this parsing logic (or extract it to a shared location like `TMDB.Mapper`) to avoid duplication.

### 1.3 Auto-Track on Library Change

The `ReleaseTracking.Refresher` GenServer already subscribes to `library:updates` PubSub events. Extend its `handle_info` for library updates to:

1. When a new TV series entity appears (not already tracked):
   - Query its status from the Library
   - If active (`:returning`, `:in_production`, or `:planned`) → auto-create a tracking item with `source: :library`
   - Fetch releases via existing `Helpers.fetch_tv_releases/4`
   - Download poster via existing `ImageStore`
   - Create `:began_tracking` event
   - Broadcast `:releases_updated` to `release_tracking:updates`

2. When a new movie appears that belongs to a TMDB collection:
   - Check if collection has unreleased entries
   - If so → auto-create tracking item with `source: :library`

3. Skip if already tracked (existing dedup check on `{tmdb_id, media_type}` unique index handles this).

### 1.4 Existing Library Migration

For TV series already in the library before this feature ships, status will be `nil`. Two approaches:

- **Lazy**: Next time the Refresher runs its periodic refresh cycle, it can backfill status for linked library entities.
- **One-time**: A mix task or Scanner pass populates status for all existing library items with TMDB IDs.

The lazy approach is simpler and consistent with the Refresher's existing role.

### 1.5 Remove "Scan Library"

Once auto-tracking is in place, the "Scan Library" button is removed. The Scanner module's bulk-discovery logic is no longer needed for the button — parts of it may be reused for the modal's suggestions in Phase 2.

---

## Phase 2: Track New Show Modal

### 2.1 UI Replacement

Replace the "Scan Library" button in the Upcoming page header with **"Track New Show"**. Same position, triggers a modal.

### 2.2 Modal Layout (Stacked)

```
┌─────────────────────────────────────┐
│  Track New Show                   ✕ │
├─────────────────────────────────────┤
│                                     │
│  Suggested from your library        │
│  ┌──────┐ ┌──────┐ ┌──────┐  >>>   │
│  │poster│ │poster│ │poster│        │
│  │      │ │      │ │      │        │
│  │ +Trk │ │ +Trk │ │ +Trk │        │
│  └──────┘ └──────┘ └──────┘        │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  Search movies & shows…     │   │
│  └─────────────────────────────┘   │
│                                     │
│  (search results appear here)       │
│                                     │
└─────────────────────────────────────┘
```

**Sections**:

1. **Suggestions row** — horizontal scrollable poster cards. Populated by a lightweight scan on modal open. Shows untracked library items with upcoming releases. Each card has poster, name, and one-click "Track" button with smart defaults.

2. **Search bar** — text input with debounced TMDB search. Searches both movies and TV shows simultaneously.

3. **Search results** — list below the search bar. Each result shows poster thumbnail, title, year, and type badge (TV/Movie).

### 2.3 Suggestions Logic

`ReleaseTracking.suggest_trackable_items/0` — returns untracked library items that have:
- A TMDB external ID
- Active production status (`:returning`, `:in_production`, `:planned` for TV; unreleased for movies)
- Upcoming releases on TMDB

This reuses Scanner's discovery logic but returns results without persisting. In practice, suggestions will be rare once auto-tracking is active — primarily for:
- Library items added before auto-tracking shipped (migration stragglers)
- Movies in collections with unreleased entries
- Series whose status changed from ended/canceled to returning (rare but real — revivals, uncancellations)

If there are no suggestions, the section is hidden and the search bar moves up.

### 2.4 Search Flow

`ReleaseTracking.search_tmdb/1` — wraps `TMDB.Client.search_movie/1` and `search_tv/1` in parallel, merges results. Returns unified list: `%{tmdb_id, media_type, name, year, poster_path, already_tracked}`.

Results that are already tracked show a "Tracking" indicator instead of an action button.

### 2.5 Tracking Actions

**Clicking a suggestion card** — one-click track with smart defaults:
- TV: `last_library_season/episode` auto-populated from Library
- Movie: tracked as-is
- Card shows "Tracking" confirmation, then fades or is removed

**Clicking a TV search result** — inline scope picker expands:
- **Smart default**: If the show is in the library, default to "Track from S{N}" (where N = last library season + 1). If not in library, default to "All upcoming".
- **Override options**: "All upcoming", "From S{N} (your library)", "Custom: S__ E__"
- Confirm button finalizes tracking

**Clicking a movie search result** — tracks immediately, unless TMDB shows it's part of a collection with other unreleased entries:
- If collection detected: inline prompt "Track just this movie, or the whole {Collection Name}?"
- Confirm choice → track accordingly

### 2.6 Tracking Function

`ReleaseTracking.track_from_search/2` — accepts a search result map and options:

```elixir
ReleaseTracking.track_from_search(
  %{tmdb_id: 12345, media_type: :tv_series, name: "Show Name", poster_path: "/abc.jpg"},
  %{start_season: 4, start_episode: 1}
)
```

Internally:
1. Creates Item via existing `track_item/1` with `source: :manual`
2. Fetches releases via existing `Helpers.fetch_tv_releases/4` or `fetch_collection_releases/1`
3. Downloads poster via existing `ImageStore.download_poster/2`
4. Creates `:began_tracking` event
5. Broadcasts `:releases_updated` — Upcoming zone auto-reloads

### 2.7 LiveView Integration

**New component**: `TrackModal` in `lib/media_centarr_web/components/track_modal.ex`

Follows the always-in-DOM modal pattern:
- `data-state="open"/"closed"` toggles visibility
- No `:if={}` conditional rendering
- Escape / click-away closes

**New assigns in LibraryLive**:
- `track_modal_open` (boolean)
- `track_suggestions` (list, loaded async on open)
- `track_suggestions_loading` (boolean)
- `track_search_query` (string)
- `track_search_results` (list)
- `track_search_loading` (boolean)
- `track_scope_item` (map or nil — the TV result currently showing scope picker)
- `track_collection_item` (map or nil — the movie result showing collection prompt)

**Events**:
- `"open_track_modal"` — opens modal, spawns async suggestion scan
- `"close_track_modal"` — closes modal, clears transient state
- `"track_search"` — debounced search, calls `ReleaseTracking.search_tmdb/1`
- `"track_suggestion"` — one-click track from suggestion card
- `"select_search_result"` — for TV: shows scope picker; for movie: checks collection
- `"confirm_track"` — finalizes with chosen scope/collection options
- `"clear_search"` — clears search input and results

### 2.8 Data Flow

```
User clicks "Track New Show"
  → track_modal_open = true
  → Spawn async Task: ReleaseTracking.suggest_trackable_items()
  → Suggestions load, pushed to track_suggestions assign

User types in search bar (debounced 300ms)
  → "track_search" event
  → ReleaseTracking.search_tmdb(query)
  → Results pushed to track_search_results

User clicks suggestion card
  → ReleaseTracking.track_from_search(result, smart_defaults)
  → PubSub broadcast → Upcoming zone reloads
  → Card shows "Tracking" state

User clicks TV search result
  → track_scope_item = result (scope picker appears inline)
  → User picks scope → "confirm_track"
  → ReleaseTracking.track_from_search(result, scope)
  → PubSub broadcast → Upcoming zone reloads

User clicks movie search result
  → If no collection: track_from_search(result, %{})
  → If collection: track_collection_item = result (prompt appears)
    → User picks movie-only or collection → "confirm_track"
    → track_from_search(result, choice)
  → PubSub broadcast → Upcoming zone reloads
```

---

## Architectural Compliance

- **Bounded context boundaries (ADR-029)**: All new logic lives in ReleaseTracking. Library gets a status field but no tracking logic. No cross-context function calls — only PubSub events.
- **PubSub for cross-context communication**: Auto-tracking is triggered by `library:updates` events, not direct calls. Tracking results broadcast via `release_tracking:updates`.
- **Pipeline as mediator**: The pipeline writes status to Library during its normal metadata extraction. It doesn't trigger tracking directly — that happens downstream via PubSub.
- **GenServer API boundary (ADR-026)**: Refresher's auto-tracking goes through ReleaseTracking's public API.
- **LiveView logic extraction (ADR-030)**: Suggestion filtering, search merging, and smart default calculation are pure functions tested independently.
- **Always-in-DOM modal pattern**: TrackModal follows ModalShell's `data-state` approach.
- **Zero warnings policy**: All new code compiles warning-free.
- **Test-first**: Both phases require tests before implementation.

## Reusable Components

| Component | Location | Reuse |
|-----------|----------|-------|
| `TMDB.Client.search_movie/2`, `search_tv/2` | `lib/media_centarr/tmdb/client.ex` | Search flow |
| `ReleaseTracking.Extractor.extract_tv_status/1` | `lib/media_centarr/release_tracking/extractor.ex` | Status parsing (shared with Mapper) |
| `ReleaseTracking.Helpers.fetch_tv_releases/4` | `lib/media_centarr/release_tracking/helpers.ex` | Release fetching for new tracked items |
| `ReleaseTracking.ImageStore` | `lib/media_centarr/release_tracking/image_store.ex` | Poster download |
| `ReleaseTracking.track_item/1` | `lib/media_centarr/release_tracking.ex` | Item creation |
| `ModalShell` pattern | `lib/media_centarr_web/components/modal_shell.ex` | Always-in-DOM modal reference |
| `Scanner.scan/0` logic | `lib/media_centarr/release_tracking/scanner.ex` | Suggestion discovery (extract and reuse) |

## Testing Strategy

**Phase 1:**
- Unit: Status extraction in Mapper, status field changesets
- Integration: Pipeline persists status on new TV series/movie
- Integration: Refresher auto-creates tracking item when active TV series appears in library
- Integration: Refresher ignores ended/canceled series

**Phase 2:**
- Unit: `suggest_trackable_items/0` returns correct candidates
- Unit: `search_tmdb/1` merges and sorts results correctly
- Unit: Smart default calculation (library end → start season)
- Unit: `track_from_search/2` creates item with correct scope
- LiveView: Modal open/close lifecycle, event handling
