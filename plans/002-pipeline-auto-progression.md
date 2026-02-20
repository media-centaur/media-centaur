# 002 — Pipeline Auto-Progression

## Goal

Wire up automatic state transitions so that after `:detect`, files flow through `:search` → `:fetch_metadata` without manual intervention. Low-confidence matches stop at `:pending_review` for human review via the UI.

## Current State

- `Watcher.detect_file/1` calls `Ash.create(:detect)` which parses the filename and creates a `WatchedFile` in state `:detected`. Nothing happens after that.
- `:search` and `:fetch_metadata` are separate Ash update actions that must be called manually.
- The confidence threshold (default 0.85) determines whether search results are `:approved` or `:pending_review`.
- `:fetch_metadata` transitions to `:fetching_images` on success.

## Design

### Approach: `after_action` hooks on WatchedFile actions

Use Ash `after_action` lifecycle hooks to trigger the next pipeline step. This keeps progression logic co-located with the actions that produce state transitions, avoids GenServer complexity, and leverages Ash's built-in lifecycle system.

### Flow

```
:detect → after_action → call :search
:search → after_action → if state == :approved, call :fetch_metadata
:search → after_action → if state == :pending_review, stop (wait for UI)
:fetch_metadata → after_action → call :download_images (plan 003)
```

### Error handling

If any step fails, the action's change module already sets `state: :error` and populates `error_message`. The `after_action` hook only fires on success, so errors naturally stop progression.

## Implementation Steps

### Step 1: Add `after_action` hook to `:detect` action

**File:** `lib/media_manager/library/watched_file.ex`

Add an `after_action` callback to the `:detect` action that triggers `:search`:

```elixir
create :detect do
  accept [:file_path]

  change set_attribute(:state, :detected)
  change MediaManager.Library.WatchedFile.Changes.ParseFileName

  change after_action(fn _changeset, file, _context ->
    case file |> Ash.Changeset.for_update(:search, %{}) |> Ash.update() do
      {:ok, updated} -> {:ok, updated}
      {:error, reason} ->
        Logger.warning("Pipeline: auto-search failed for #{file.id}: #{inspect(reason)}")
        {:ok, file}
    end
  end)
end
```

Note: If search fails, we still return `{:ok, file}` so the `:detect` action succeeds — the file stays at `:detected` state and can be retried. Add `require Logger` to the module.

### Step 2: Add `after_action` hook to `:search` action

**File:** `lib/media_manager/library/watched_file.ex`

Add an `after_action` callback that triggers `:fetch_metadata` only when the file was auto-approved:

```elixir
update :search do
  require_atomic? false
  change set_attribute(:state, :searching)
  change MediaManager.Library.WatchedFile.Changes.SearchTmdb

  change after_action(fn _changeset, file, _context ->
    if file.state == :approved do
      case file |> Ash.Changeset.for_update(:fetch_metadata, %{}) |> Ash.update() do
        {:ok, updated} -> {:ok, updated}
        {:error, reason} ->
          Logger.warning("Pipeline: auto-fetch failed for #{file.id}: #{inspect(reason)}")
          {:ok, file}
      end
    else
      {:ok, file}
    end
  end)
end
```

### Step 3: Add `require Logger` to WatchedFile module

**File:** `lib/media_manager/library/watched_file.ex`

Add `require Logger` at the top of the module body so the Logger macro is available inside the `after_action` closures.

## Files Changed

| File | Change |
|------|--------|
| `lib/media_manager/library/watched_file.ex` | Add `require Logger`, add `after_action` hooks to `:detect` and `:search` actions |

## Testing

No new tests per the testing strategy — this is GenServer/state-machine wiring that changes frequently. Verify manually by dropping a video file in `media_dir` and confirming it flows through to `:fetching_images` (or `:pending_review` for low-confidence matches).

## Future: Manual approval trigger

When the UI approves a `:pending_review` file (sets `tmdb_id` and transitions to `:approved`), the same `after_action` pattern on an `:approve` action will trigger `:fetch_metadata`. This is out of scope for this plan but the pattern is identical.
