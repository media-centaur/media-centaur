# Library Removal: Dismiss & Delete

## Context

Users have no way to remove content from the library. Once a file is detected and ingested, it stays forever. Two distinct needs:

1. **Dismiss** — "Hide this, keep the files." Shared drives, misidentified content, stuff the user doesn't want in the media center.
2. **Delete** — "Remove the files from disk." Permanent removal with an adaptive confirmation dialog that describes exactly what will be deleted based on the actual folder structure.

## Design

### Core Mechanism: WatchedFile `:ignored` State

Adding `:ignored` to WatchedFile's state enum is the single key change. It sits cleanly outside the existing `:complete`/`:absent` lifecycle — every existing code path (scan, absent tracking, TTL expiry, restore) naturally excludes it with zero changes. Only the pipeline's `already_linked?` needs a one-line extension.

### Dismiss Operation

1. Load entity's WatchedFiles
2. Bulk update: `state: :ignored`, `entity_id: nil` (FK constraint requires nulling before entity deletion)
3. EntityCascade (destroys entity, children, images from DB and disk)
4. Broadcast `{:entities_changed, [entity_id]}`

Files stay on disk. On next scan or inotify event, the `:ignored` WatchedFile prevents re-processing.

### Delete Operation

1. Load entity's WatchedFiles, collect all file paths
2. Compute deletion summary (for the confirmation dialog — see below)
3. After user confirms:
   - Destroy WatchedFile records
   - EntityCascade (entity, children, images)
   - Delete physical video files from disk
   - Walk up from each deleted file's parent → watch_dir root, deleting empty directories (`File.rmdir/1` only succeeds on empty dirs — inherently safe)
   - Broadcast `{:entities_changed, [entity.id]}`

Always deletes the entire entity. No per-season granularity.

### Adaptive Deletion Summary

Compute a human-readable description of what will be deleted, based on actual folder structure:

**Analysis function** takes the entity's file paths + watch_dir and returns:
- `root_dir` — longest common directory prefix (stopping at watch_dir)
- `file_count` — total video files
- `season_count` — from entity hierarchy (TV series only)
- `folder_description` — adaptive text

Examples:
- Movie in folder: `Delete "Sample Movie Two"? This will permanently delete: /videos/Sample.Movie.Two.1991/ (1 file)`
- Loose movie file: `Delete "Sample Movie Two"? This will permanently delete: 1 file`
- TV series in one tree: `Delete "Citadel 5"? This will permanently delete: /videos/Citadel 5/ (5 seasons, 110 files)`
- TV series with scattered files: `Delete "Sample Show Four"? This will permanently delete: 6 files across 6 folders`

### Review Dismiss Bug Fix

Currently, dismissing a PendingFile in Review sets `status: :dismissed` but creates no WatchedFile. On next scan, the file isn't in `known_paths`, gets re-detected, and the dismiss doesn't stick.

Fix: when dismissing a PendingFile, also create an `:ignored` WatchedFile for that path. Prevents re-detection.

### inotify Race (Non-Issue)

When we delete files, Watcher also detects deletion (3s debounce) and FileTracker runs cleanup. But by then WatchedFiles are already destroyed, so `list_files_by_paths!` returns `[]` — harmless no-op. Already idempotent, no changes needed.

## Implementation

### Step 1: Data Model

**`lib/media_centaur/library/types/watched_file_state.ex`**
- Add `:ignored` to enum values

**`lib/media_centaur/library/watched_file.ex`**
- Add `:mark_ignored` update action — sets `state: :ignored`, accepts `entity_id: nil`
- Add `:create_ignored` create action — for Review dismiss (path has no existing WatchedFile)

**Migration**: `mix ash_sqlite.generate_migrations --name add_ignored_state`

### Step 2: Pipeline Skip Check

**`lib/media_centaur/pipeline.ex:261`**
- Rename `already_linked?` → `should_skip?`
- Add clause: `[%{state: :ignored}] -> true`

### Step 3: Library.Removal Module

**New file: `lib/media_centaur/library/removal.ex`**

Two public functions:

`dismiss_entity!(entity)`:
1. `Library.list_watched_files_for_entity!(entity.id)` (need to add this if missing)
2. Bulk update WatchedFiles → `:ignored`, null `entity_id`
3. `EntityCascade.destroy!(entity)`
4. Broadcast `{:entities_changed, [entity.id]}`

`delete_entity!(entity)`:
1. Load WatchedFiles, collect paths + watch_dir
2. Bulk destroy WatchedFiles
3. `EntityCascade.destroy!(entity)`
4. Delete files: `Enum.each(paths, &File.rm/1)`
5. Clean up empty dirs: for each unique parent dir, walk up deleting empty dirs until watch_dir
6. Broadcast `{:entities_changed, [entity.id]}`

`deletion_summary(entity)`:
1. Load WatchedFiles with file paths
2. Compute common ancestor dir, file count, season count
3. Return struct with `root_dir`, `file_count`, `season_count`, `description` for UI

### Step 4: Review Dismiss Fix

**`lib/media_centaur/review.ex:157`**
- After `dismiss_pending_file`, create `:ignored` WatchedFile with the pending file's `file_path` and `watch_directory`

### Step 5: UI — Detail Panel Actions

**`lib/media_centaur_web/live/library_live.ex`** and detail panel component:

Add to entity detail panel:
- "Dismiss" button (btn-ghost) — confirmation: "Remove from library? Files will remain on disk."
- "Delete" button (btn-soft btn-error) — shows adaptive deletion summary, requires confirmation

Handle events:
- `"dismiss_entity"` → `Library.Removal.dismiss_entity!(entity)`
- `"request_delete"` → compute `deletion_summary`, show confirmation modal
- `"confirm_delete"` → `Library.Removal.delete_entity!(entity)`

After either operation: close detail panel, entity disappears from grid via PubSub.

### Step 6: Tests

- WatchedFile `:mark_ignored` action test
- `Removal.dismiss_entity!` — verifies entity gone, WatchedFiles in `:ignored` state, files still on disk
- `Removal.delete_entity!` — verifies entity gone, WatchedFiles destroyed, files deleted, empty dirs cleaned
- Pipeline `should_skip?` — returns true for `:ignored` WatchedFiles
- Review dismiss — creates `:ignored` WatchedFile
- `deletion_summary` — correct file counts and folder descriptions for various structures

## Critical Files

| File | Change |
|------|--------|
| `lib/media_centaur/library/types/watched_file_state.ex` | Add `:ignored` |
| `lib/media_centaur/library/watched_file.ex` | Add `:mark_ignored`, `:create_ignored` actions |
| `lib/media_centaur/pipeline.ex` | Rename + extend skip check |
| `lib/media_centaur/library/removal.ex` | **New** — dismiss/delete orchestration |
| `lib/media_centaur/library/entity_cascade.ex` | Reuse (no changes) |
| `lib/media_centaur/library/file_tracker.ex` | Reference for cleanup patterns (no changes) |
| `lib/media_centaur/review.ex` | Dismiss fix |
| `lib/media_centaur_web/live/library_live.ex` | UI event handlers |
| Detail panel component | Dismiss/Delete buttons + confirmation |

## Verification

1. **Dismiss**: Dismiss entity → gone from library → scan → NOT re-ingested → WatchedFile has `:ignored` state
2. **Delete**: Delete entity → files gone from disk → empty parent dirs cleaned → entity gone from DB → confirmation showed correct summary
3. **Review dismiss**: Dismiss pending file → restart → stays dismissed
4. **inotify idempotency**: Delete via action → wait 5s → no errors in logs
5. `mix precommit` passes
