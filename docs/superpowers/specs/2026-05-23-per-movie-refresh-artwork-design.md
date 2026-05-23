# Per-movie "Refresh artwork" — design

**Date:** 2026-05-23
**Status:** Approved, implementing

## Problem

A movie can end up with no displayed artwork (e.g. "Io Marinaio" shows a
placeholder). The only way to re-fetch artwork today is **Settings → Refresh
image cache**, which clears and re-enqueues *every* entity. There is no way to
say "re-fetch artwork for *this one* movie" from the detail page.

## Goal

Add a **Refresh artwork** action to the detail → manage (info) view that
re-fetches the entity's TMDB metadata and re-downloads its artwork,
**replacing** existing art and **filling gaps** when there is none.

## Why the existing mechanisms don't fit

Both bulk mechanisms iterate over **existing `Image` records**, so neither helps
a movie that has *no* `Image` record at all:

- `Maintenance.refresh_image_cache/0` — clears all files, nulls `content_url`,
  re-broadcasts only entities that already have Image records + files.
- `Pipeline.ImageRepair.repair_all/0` — rebuilds queue rows for `Image` records
  whose files are *missing* (`ImageHealth.list_missing/0`).

The **import pipeline**, by contrast, derives the image list straight from TMDB
data and enqueues it — creating `Image` records on download via
`upsert_image(_, [:owner_type, :owner_id, :role])`. That is exactly
"refresh & replace", so the per-movie button reuses the **import enqueue path**,
not the repair path.

## Architecture

Componentized to avoid duplication (single responsibility per module):

1. **Extract `build_images/1`** (currently private in
   `Pipeline.Stages.FetchMetadata`) into a shared pure mapper —
   `MediaCentaur.TMDB.Mapper.image_list/1` (TMDB data map → `[%{role, url,
   extension}]`). `FetchMetadata` delegates to it; the new refresh path calls it
   too. One source of truth for "TMDB data → image list".

2. **Extract entity→context lookups** (`find_tmdb_context/2`, `find_watch_dir/2`)
   that are currently private in `Pipeline.ImageRepair` into a shared
   `MediaCentaur.Pipeline.EntityImageContext` (one job: locate the tmdb id +
   watch_dir for an entity). `ImageRepair` and the new module both depend on it.

3. **New module `MediaCentaur.Pipeline.ImageRefresh`** — one job: force re-fetch
   + re-enqueue *all* artwork for one entity from TMDB.
   - `refresh_entity(entity_id, type) :: {:ok, non_neg_integer()} | {:error, reason}`
   - Resolves tmdb id + watch_dir via `EntityImageContext`.
   - Fetches metadata: `TMDB.Client.get_movie/1` | `get_tv/1` | `get_collection/1`
     by type (`:movie`, `:video_object` → movie; `:tv_series` → tv;
     `:movie_series` → collection).
   - Builds image list via the extracted mapper.
   - Broadcasts `{:enqueue_images, %{entity_id, watch_dir, images: pending}}` on
     `Topics.pipeline_images/0` (the import path). The Producer creates queue
     rows (`ImageQueue.create/1` upserts to pending) and triggers download;
     `upsert_image/2` replaces `content_url` on completion.
   - `{:error, :no_tmdb_id}` when the entity isn't identified; `{:error, reason}`
     on TMDB failure.
   - `Log.info(:library, "image_refresh: …")` at start and result.

## UI

- **`detail_panel.ex` Actions section** — add a **Refresh artwork** button next to
  Rematch, gated on `@tmdb_ready` (same as Rematch). Non-destructive → **no
  inline confirm**, single click. Icon `hero-photo-mini` (or similar),
  `variant="ghost"`, `size="sm"`, `phx-click="refresh_artwork"
  phx-value-id={@entity.id}`, `data-nav-item tabindex="0"`.
- **`entity_modal.ex`** — `handle_event("refresh_artwork", %{"id" => id}, socket)`:
  runs `ImageRefresh.refresh_entity/2` in a supervised `Task`
  (`MediaCentaur.TaskSupervisor`) since it does network I/O, then flashes
  "Refreshing artwork from TMDB…". On `{:error, :no_tmdb_id}` flash "No TMDB
  match — Rematch first." The existing `{:entities_changed, [id]}` broadcast
  refreshes the open modal when art lands.
- Update the **detail_panel info-view story** variation to include the new button
  (MC0009).

## Scope

- **In:** the top-level entity in the manage view — `:movie`, `:tv_series`,
  `:movie_series`, `:video_object`.
- **Out:** per-episode thumbs (no per-episode manage view); orphaned-role
  cleanup (a role TMDB no longer returns is left in place) — YAGNI.

## Testing (test-first)

- Unit: `ImageRefresh.refresh_entity/2` with the TMDB stub — asserts queue rows
  created + `{:enqueue_images, …}` broadcast for a movie; asserts
  `{:error, :no_tmdb_id}` for an unidentified entity.
- Unit: extracted `TMDB.Mapper.image_list/1` and `EntityImageContext` behave
  identically to the originals (poster/backdrop/logo extraction; tmdb id +
  watch_dir resolution per type).
- LiveView: `entity_modal` (or detail) `*_live_test.exs` — clicking "Refresh
  artwork" triggers the refresh and flashes; button hidden when `!@tmdb_ready`.

## Observability

`MediaCentaur.Log.info(:library, …)` at refresh start and result (count / error),
visible in the Console drawer.
