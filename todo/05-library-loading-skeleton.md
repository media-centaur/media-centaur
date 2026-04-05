# Library initial-load skeleton / loading feedback

**Source:** design-audit 2026-04-06, DS17
**Severity:** Moderate
**Scope:** `lib/media_centaur_web/live/library_live.ex`

## Context

`LibraryLive.handle_params/3` calls `load_library/1` synchronously on first navigation when `entries == []`:

```elixir
def handle_params(params, _uri, socket) do
  socket =
    if connected?(socket) && socket.assigns.entries == [] do
      load_library(socket)
    else
      socket
    end
  ...
```

`load_library/1` calls `LibraryBrowser.fetch_all_typed_entries/0`, which hits the database with full preloads for every typed entity (movies, tv_series, movie_series, video_objects plus their seasons/episodes/images). For a small library this is fast; for a large one, it blocks the LiveView mount and the user sees a blank page until the whole fetch returns.

There is no skeleton, no spinner, no `phx-loading-*` affordance.

## What to do

Wrap the fetch in `assign_async/3` so the initial render returns immediately with a `loading` state, then the actual grid data arrives via an async message.

1. Restructure `handle_params/3` so the `:entries == []` branch kicks off an `assign_async` instead of calling `load_library/1` synchronously.
2. Use the `%AsyncResult{}` wrapper (via `assign_async`) for `entries`, `resume_targets`, and `playback`. The existing `recompute_continue_watching/1` and `recompute_counts/1` helpers run after the async resolves.
3. In the render, when the async result is still loading and `grid_count == 0`, render a skeleton grid: a `grid grid-cols-[repeat(auto-fill,minmax(155px,1fr))] gap-3` with ~18 empty `<div class="aspect-[2/3] glass-inset rounded-lg animate-pulse" />` tiles. Use `phx-mounted` for any entrance transition, **never** CSS keyframe `animation` on stream items (CLAUDE.md rule — `animate-pulse` on skeleton tiles is fine because they are NOT in a LiveView stream, they're rendered inline during the loading state).
4. For Continue Watching zone, show the same kind of placeholder using 16:9 aspect.
5. Make sure the PubSub reload branches (`{:entities_changed, ...}`, `:reload_entities`, progress updates) don't re-trigger the async path — they should continue to mutate the already-loaded state.

## Acceptance criteria

- Opening `/` with a cold LiveView mount shows skeleton tiles while data loads, then transitions to the real grid.
- Switching zones (already-loaded case) still uses `push_patch` with no blank frame.
- Elixir tests still green.
- `mix precommit` clean.
- Manually verify by `scripts/install-dev` → open Chrome DevTools MCP → `navigate_page("http://127.0.0.1:4001/")` → `take_screenshot` during load.
