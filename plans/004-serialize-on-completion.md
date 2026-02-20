# 004 — Serialize Library on Pipeline Completion

## Goal

Trigger `JsonWriter.regenerate_all` after an entity's pipeline reaches `:complete`, so that `media.json` is always up-to-date with the latest entity data and downloaded image paths.

## Current State

- `JsonWriter` is a GenServer that can `regenerate_all` — reads all entities with associations, serializes them, and atomically writes `media.json`.
- `JsonWriter` already subscribes to `"watcher:state"` PubSub topic but the handlers are no-ops.
- After plan 003, `WatchedFile` transitions to `:complete` when images finish downloading.
- There is no automatic trigger to serialize after pipeline completion.

## Design

### Approach: PubSub broadcast from `:download_images` `after_action`

When `WatchedFile` reaches `:complete` state, broadcast a `{:pipeline_complete, entity_id}` message on a `"pipeline:events"` PubSub topic. `JsonWriter` subscribes to this topic and calls `do_regenerate_all/1` in response.

This keeps the coupling loose — the pipeline doesn't call `JsonWriter` directly, and `JsonWriter` can react to completion events from any source.

### Why PubSub over direct call?

- `JsonWriter` is a GenServer; calling it from inside an Ash action (which runs in the caller's process) via `GenServer.call` works but creates a synchronous dependency.
- PubSub `broadcast` is fire-and-forget from the action's perspective — the pipeline finishes without waiting for serialization.
- Other consumers (e.g., LiveView for real-time UI updates) can also subscribe to `"pipeline:events"` later.

## Implementation Steps

### Step 1: Broadcast pipeline completion from `:download_images`

**File:** `lib/media_manager/library/watched_file.ex`

Add an `after_action` hook to the `:download_images` action:

```elixir
update :download_images do
  require_atomic? false
  change MediaManager.Library.WatchedFile.Changes.DownloadImages

  change after_action(fn _changeset, file, _context ->
    if file.state == :complete do
      Phoenix.PubSub.broadcast(
        MediaManager.PubSub,
        "pipeline:events",
        {:pipeline_complete, file.entity_id}
      )
    end

    {:ok, file}
  end)
end
```

### Step 2: Subscribe `JsonWriter` to `"pipeline:events"`

**File:** `lib/media_manager/json_writer.ex`

In `init/1`, add a subscription:

```elixir
def init(_) do
  Phoenix.PubSub.subscribe(MediaManager.PubSub, "watcher:state")
  Phoenix.PubSub.subscribe(MediaManager.PubSub, "pipeline:events")
  {:ok, %{}}
end
```

### Step 3: Handle `{:pipeline_complete, entity_id}` in `JsonWriter`

**File:** `lib/media_manager/json_writer.ex`

Add a `handle_info` clause:

```elixir
@impl true
def handle_info({:pipeline_complete, entity_id}, state) do
  Logger.info("JsonWriter: pipeline complete for entity #{entity_id}, regenerating media.json")
  do_regenerate_all(MediaManager.Config.get(:shared_media_library))
  {:noreply, state}
end
```

Add `require Logger` at the top of the module.

## Files Changed

| File | Change |
|------|--------|
| `lib/media_manager/library/watched_file.ex` | Add `after_action` PubSub broadcast on `:download_images` |
| `lib/media_manager/json_writer.ex` | Add `require Logger`, subscribe to `"pipeline:events"`, handle `{:pipeline_complete, _}` |

## Testing

No new tests per testing strategy. Verify manually:
1. Drop a video file in `media_dir`.
2. Confirm it flows through detect → search → fetch_metadata → download_images → complete.
3. Check that `media.json` is written at the `shared_media_library` path automatically and contains the entity with populated `contentUrl` fields in its `image` array.

## Future Considerations

- **Debouncing:** If multiple files complete in quick succession, `regenerate_all` will be called for each. Since it's an atomic write of the full library, this is correct but slightly wasteful. A debounce (e.g., 500ms delay, reset on each new event) could coalesce rapid completions. Not needed for v1.
- **LiveView updates:** Other subscribers to `"pipeline:events"` can update the UI in real-time when a file completes. Out of scope for this plan.
