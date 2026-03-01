# File Removal Detection and Presence Tracking

## Problem Statement

Deleted or unmounted media files leave stale records in the database. The UI shows unplayable entities with no indication files are gone. The only recovery is the nuclear "Clear Database" admin button. Users who delete a folder of shows or unplug a USB drive see phantom entries that break on play.

## User-Facing Behavior

- **File deleted**: within a few seconds, the entity disappears from the frontend and LiveView. All related records and cached images are cleaned up immediately.
- **Folder deleted**: same behavior, debounced — a 40-episode folder deletion produces one batched cleanup, not 40 individual updates.
- **Drive unmounted / disconnected**: all entities sourced from that drive disappear from the frontend immediately. Database records are retained. When the drive returns, entities reappear. If the drive doesn't return within a configurable TTL, records and images are purged.
- **Partial absence**: a TV series where some episodes are on a disconnected drive shows only the present episodes. A movie series where some movies are gone adjusts its presentation automatically (the serializer already handles the 1-child → standalone Movie case).

## Design

### Two Cleanup Paths

**Path 1 — Confirmed Deletion (immediate)**

inotify fires `:deleted` events. The Watcher collects these, debounces for ~3 seconds, then broadcasts `{:files_removed, [%{path, watch_dir}]}` to a PubSub topic (e.g. `"pipeline:removals"` or `"library:file_events"`). A new GenServer — the **file presence tracker** — subscribes and performs immediate cleanup:

1. Look up WatchedFile records by `file_path` for each removed path
2. Identify child records (Episode, Movie, Extra) where `content_url` matches the file path
3. Delete those child records and their Image records (DB + disk)
4. Delete the WatchedFile records
5. Check parent entities: if a Season now has zero Episodes, delete the Season. If an Entity now has zero WatchedFiles, delete the Entity and all remaining children (Seasons, Episodes, Movies, Extras, Identifiers, Images — DB records and image files on disk)
6. Broadcast `{:entities_changed, entity_ids}` for all affected entities

**Path 2 — Unavailability (deferred via TTL)**

When a filesystem unmounts or the Watcher transitions to `:unavailable`, the file presence tracker receives the existing `{:watcher_state_changed, dir, :unavailable}` PubSub event and:

1. Finds all WatchedFiles where `watch_dir` matches the unavailable directory and `state` is `:complete`
2. Bulk-updates them to `state: :absent`, sets `absent_since` to now
3. Broadcasts `{:entities_changed, entity_ids}` for all affected entities

The channel handler and LiveView filter: entities with zero `:complete` WatchedFiles are not pushed to the frontend. Entities with a mix of present and absent files are serialized showing only present content (absent episodes/movies/extras are excluded from serialization).

**Restoration on remount**: when the Watcher transitions back to `:watching`, it runs a scan. The scan logic is extended: if a file is found that has an `:absent` WatchedFile, it flips the state back to `:complete` and clears `absent_since`. The entity reappears in the frontend.

**TTL expiration**: a periodic check (daily cadence, configurable) queries for WatchedFiles in `:absent` state where `absent_since` is older than the configured TTL. For each batch of expired files, runs the same cleanup cascade as Path 1.

### Data Model Changes

**WatchedFile resource** (`lib/media_centaur/library/watched_file.ex`):
- Add `:absent` to `WatchedFileState` enum
- Add `absent_since` attribute (`utc_datetime_usec`, nullable)
- Add `:mark_absent` update action (sets `state: :absent`, `absent_since: now`)
- Add `:mark_present` update action (sets `state: :complete`, clears `absent_since`)
- Add `:expired_absent` read action (filters `state == :absent AND absent_since < cutoff`)

**Config** (`defaults/backend.toml`):
- Add `file_absence_ttl_days` key (integer, default 30)

**Migration**: Ash-generated migration for the new attribute and enum value.

### New Module: File Presence Tracker

`lib/media_centaur/library/file_tracker.ex` — a GenServer in the Library context.

**Supervision**: added to the application supervision tree after the Pipeline.

**Subscriptions**:
- PubSub topic for file removal events (broadcast by Watcher)
- `"watcher:state"` for `{:watcher_state_changed, dir, state}` events

**Responsibilities**:
- Handle `{:files_removed, paths}` → immediate cleanup cascade
- Handle `{:watcher_state_changed, dir, :unavailable}` → bulk mark absent
- Handle `{:watcher_state_changed, dir, :watching}` → no-op (scan handles restoration)
- Schedule periodic TTL check (daily)
- TTL check → query expired absent files → run cleanup cascade

**Cleanup cascade** (shared logic for both paths):
1. Given a list of WatchedFile records to remove:
2. Group by `entity_id`
3. For each entity, find child records (Episode/Movie/Extra) matching `content_url` in the removed file paths
4. Delete child records and their images (DB + disk)
5. Delete the WatchedFiles
6. For TV series: delete empty Seasons
7. For any entity: if zero WatchedFiles remain, delete Entity and all remaining children, identifiers, images
8. Collect all affected entity IDs (including fully deleted ones), broadcast `{:entities_changed, entity_ids}`

**Image cleanup on disk**: when deleting an Image record that has a `content_url`, resolve the path via `Config.resolve_image_path/1` and delete the file. When deleting an Entity's last Image owner directory, remove the UUID directory itself.

### Watcher Changes

`lib/media_centaur/watcher.ex`:

- In `handle_info({:file_event, _pid, {path, events}}, state)`: add a clause for `:deleted` events on video files. Instead of broadcasting immediately, accumulate deleted paths in a debounce buffer (map of `path => watch_dir` in GenServer state).
- Add a debounce timer (~3 seconds). When it fires, broadcast `{:files_removed, collected_paths}` and clear the buffer. Reset the timer on each new deletion event (sliding window).
- On `:unmounted` event: the existing `broadcast_state(state.dir, :unavailable)` is already emitted. The file presence tracker subscribes to `"watcher:state"` and handles it. No additional Watcher change needed for unmount.

### Channel / Serializer Changes

**LibraryChannel** (`lib/media_centaur_web/channels/library_channel.ex`):
- `build_entity_list/0` must filter: only include entities that have at least one WatchedFile in `:complete` state. Add a query filter or a new Entity read action (`:with_present_files` or similar) that joins on WatchedFiles and filters by state.
- `load_entity_payloads/1` must apply the same filter.

**Serializer** (`lib/media_centaur/serializer.ex`):
- For TV series: filter out episodes where `content_url` is nil or whose file is absent. This requires the serializer to know which files are present. Two approaches:
  - (a) The channel handler pre-filters the loaded associations before serializing (strip absent episodes/movies/extras from the loaded entity struct)
  - (b) The serializer receives a set of present file paths and filters internally
- Approach (a) is simpler and keeps the serializer pure. The channel handler (or a helper) strips absent children before passing to `Serializer.serialize_entity/1`.

**LiveView** (`lib/media_centaur_web/live/library_live.ex`):
- Apply the same "only entities with present files" filter when loading entities for display.

### Scan Changes

`lib/media_centaur/watcher.ex` — `scan_directory/1`:
- Currently fetches known file paths and skips them entirely
- Extend: also fetch WatchedFiles in `:absent` state. If a file is found on disk that has an `:absent` WatchedFile, flip it back to `:complete` (via the `:mark_present` action) and include its entity_id in a restoration broadcast.
- This handles drive remount: watcher goes `:watching` → scan runs → absent files found on disk → restored.

### Integration Points

- **PubSub topics**: new topic for file removal events (or reuse `"pipeline:input"` with a new event shape — but a separate topic is cleaner since this isn't pipeline input)
- **Channel messages**: no new message types. Uses existing `library:entities` (for updated entities) and `library:entities_removed` (for deleted entities). The channel handler already resolves entity IDs into updated/removed sets.
- **Spec update**: `API.md` should note that `library:entities_removed` may be pushed when files are deleted or drives disconnected, not only during admin operations.

### Constraints

- ADR-003: all data access through Ash (cleanup uses Ash actions, not raw SQL)
- ADR-005: UUIDs are stable forever (no entity promotion/demotion — movie series presentation is a serializer concern)
- ADR-007: bounded contexts communicate through PubSub (Watcher broadcasts events, Library's file tracker subscribes)
- ADR-008: pipeline is a mediator, not a side effect (file removal is handled by Library, not Pipeline)
- ADR-010: PubSub-driven input (file removal follows the same pattern as file detection)
- ADR-011: all mutations broadcast `{:entities_changed, entity_ids}` (cleanup follows this contract)

## Acceptance Criteria

- [ ] Deleting a standalone movie file removes the entity from the frontend within ~5 seconds and cleans up all DB records + cached images
- [ ] Deleting a folder with a TV series (many episodes) cleans up all episodes, empty seasons, the entity, and images — debounced into a single batch operation
- [ ] Deleting 3 of 4 movies from a movie series shows the remaining movie as a standalone Movie in the frontend (serializer already handles this; verify with test)
- [ ] Deleting one episode from a multi-episode TV series removes only that episode; the series and other episodes remain
- [ ] Unmounting a drive removes all entities sourced from that drive from the frontend immediately
- [ ] Remounting the drive within TTL restores all entities to the frontend (scan flips absent → complete)
- [ ] After TTL expires, absent file records and their images are cleaned up by the periodic check
- [ ] Entities with a mix of present and absent files appear in the frontend showing only present content
- [ ] `file_absence_ttl_days` config key is documented in `defaults/backend.toml`
- [ ] Existing file detection (`:created`/`:modified`) behavior is unchanged
- [ ] Zero warnings in compilation and tests

## Decisions

See `adrs/2026-03-01-015-two-phase-file-removal.md`

## Smoke Tests

**Affected contracts**: `library:entities`, `library:entities_removed` channel messages (these are existing message types, but are now triggered by new code paths).

**Tests to add**:

- **WatchedFile resource tests** (`test/media_centaur/library/watched_file_test.exs`): test `:mark_absent`, `:mark_present`, `:expired_absent` actions
- **File tracker tests** (`test/media_centaur/library/file_tracker_test.exs`): test cleanup cascade logic — given WatchedFiles and related records, verify correct records are deleted and correct entity_ids are broadcast. Test TTL expiration query. Test unmount marking. Use `DataCase`.
- **Channel tests** (`test/media_centaur_web/channels/library_channel_test.exs`): add test cases verifying that entities with all-absent files are excluded from `library:entities` on sync, and that `library:entities_removed` is pushed when cleanup runs.
- **Serializer tests** (`test/media_centaur/serializer_test.exs`): verify TV series with some episodes stripped serializes correctly; verify movie series presentation thresholds.
- **Watcher tests**: verify debounce behavior — multiple rapid deletions produce one batched broadcast.
