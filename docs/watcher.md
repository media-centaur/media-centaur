# Watcher

The watcher subsystem monitors configured directories for video file additions and removals using Linux inotify. One `Watcher` GenServer runs per directory, coordinated by a shared supervisor.

> [Architecture](architecture.md) · **Watcher** · [Pipeline](pipeline.md) · [TMDB](tmdb.md) · [Playback](playback.md) · [Library](library.md) · [Input System](input-system.md)

- [Architecture](#architecture)
- [Key Concepts](#key-concepts)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [PubSub Events](#pubsub-events)
- [Module Reference](#module-reference)

## Architecture

```mermaid
graph TD
    Config[Config.get :media_dirs] --> Sup

    subgraph Sup["Watcher.Supervisor (one_for_all)"]
        Registry[Watcher.Registry<br/>unique keys by dir]
        DynSup[DynamicSupervisor]
    end

    DynSup --> W1["Watcher /mnt/media"]
    DynSup --> W2["Watcher /mnt/videos"]

    W1 -->|inotify| FS1[FileSystem]
    W2 -->|inotify| FS2[FileSystem]

    W1 -->|"PubSub: file_detected"| Pipeline[Pipeline Producer]
    W2 -->|"PubSub: file_detected"| Pipeline
    W1 -->|"PubSub: files_removed"| FT[FileTracker]
    W2 -->|"PubSub: files_removed"| FT
```

## Key Concepts

**Supported video extensions:** `.mkv`, `.mp4`, `.avi`, `.mov`, `.wmv`, `.m4v`, `.ts`, `.m2ts`

**Watcher states:**

```mermaid
stateDiagram-v2
    [*] --> initializing
    initializing --> watching : directory accessible
    initializing --> unavailable : directory missing
    watching --> unavailable : unmount / inaccessible
    unavailable --> watching : health check passes + auto-scan
```

- `:initializing` — starting up, not yet watching
- `:watching` — inotify active, detecting files
- `:unavailable` — directory missing or unmounted (e.g., removable drive disconnected)

**File stability check:** When a file is created or modified, the watcher polls its size twice at 5-second intervals. Only after the size stabilizes is the file broadcast as detected. This handles in-progress downloads and copies.

**Deletion debouncing:** File removals are buffered with a 3-second sliding window. All deletions in the window are flushed together in one PubSub broadcast.

## Configuration

- `media_dirs` — directories to monitor (see [configuration.md](configuration.md))
- `exclude_dirs` — paths inside a media directory to skip (absolute paths)

Both are DB-managed since v0.14.0 / v0.15.0 — edits happen in **Settings → Library** and flow through `Settings` to the watchers without a restart. The TOML holds only bootstrap state: `database_path`, `port`, and the initial `media_dirs` seed (imported once on first boot, managed in the UI thereafter).

Each watcher also auto-excludes its own images directory and staging directory.

### Runtime config updates

When media dirs or excluded dirs change, `Settings` broadcasts `:config_updated` on the `config:updates` topic. `Watcher.ConfigListener` translates that broadcast into targeted messages for each running `Watcher` (e.g. `{:config_updated, :exclude_dirs, new_list}`), which the watcher applies in place — no supervisor restart, no inotify teardown. This is what makes v0.21.0's "changes to your excluded-directory list take effect immediately" work.

Media-dir edits reconcile the running set only while watching is on (`Watcher.Supervisor.enabled?/0`, flipped by `start_watchers/0` / `stop_watchers/0` — boot and the Settings toggle). With watchers off, an edit starts nothing; turning them back on reads the current dirs.

The v0.21.0 crash fix lives in the same path: previously, creating or modifying an excluded directory could trip an unhandled message and kill the watcher; the handler now treats events for excluded paths as no-ops.

## How It Works

### File Detection

1. inotify reports a create/modify event for a file with a video extension
2. Watcher starts size stability polling (2 checks, 5 seconds apart)
3. Once stable, broadcasts `{:file_detected, %{path, media_dir}}` to `"pipeline:input"`
4. Pipeline Producer picks it up for processing

### File Removal

1. inotify reports a delete event
2. Path is buffered in the deletion queue
3. After 3 seconds with no new deletions, all buffered paths are flushed
4. Broadcasts `{:files_removed, [paths]}` to `"library:file_events"`
5. FileTracker handles cleanup

**UI-initiated deletions** bypass inotify entirely. `Library.Removal` calls `File.rm`/`File.rm_rf` and then invokes `FileTracker.cleanup_removed_files/1` directly. If the watcher's inotify also fires for the same paths (single-file deletes), the second cleanup is a no-op because `cleanup_removed_files` is idempotent. For folder deletions, `rm -rf` typically only generates a directory-level inotify event (not per-file), which the watcher ignores.

### Mount Recovery

1. Health check runs every 30 seconds
2. The watcher captures the path's device id (`{major_device, minor_device}` from `File.stat/1`) when it starts watching
3. Each tick re-stats the path and feeds the result through `Watcher.MountStatus.action/3`:
   - directory disappeared → transition to `:unavailable`
   - device id changed under `:watching` (drive mounted onto an existing empty mountpoint, or a different filesystem swapped in) → tear down the inotify watcher and re-init with `was_unavailable: true` so the recovery scan re-broadcasts entities for image re-resolution
   - directory accessible after `:unavailable` → re-init
4. Auto-scan runs after re-init to detect any files added while the directory was unavailable or while inotify was attached to a stale inode
5. State change broadcast to `"watcher:state"` PubSub topic

Why device-id tracking matters: inotify watches inodes, not paths. If a watcher attaches to an empty mountpoint at startup and a drive is mounted on top later, no inotify events ever fire — the watch is on the now-shadowed pre-mount inode. The device-id check is the only kernel-level signal that a remount happened.

### Manual Scan

The dashboard provides a "Scan directories" button that calls `Watcher.Rescan.scan/0`. This walks all watched directories recursively, detecting video files not yet tracked in the database. Each new file enters the pipeline normally.

## PubSub Events

| Topic | Event | Payload |
|-------|-------|---------|
| `pipeline:input` | `:file_detected` | `%{path: string, media_dir: string}` |
| `library:file_events` | `:files_removed` | `[path, ...]` |
| `watcher:state` | `:watcher_state_changed` | `{dir, new_state}` |

## Module Reference

| Module | Description | Path |
|--------|-------------|------|
| `MediaCentaur.Watcher` | Per-directory GenServer, inotify + PubSub. Stamps `Library.FilePresence` on detection; broadcasts `{:files_removed, paths}` on inotify delete | `lib/media_centaur/watcher.ex` |
| `MediaCentaur.Watcher.Supervisor` | Coordinates all watchers, scan/pause API, `rescan_unlinked` walks `library_file_presences` | `lib/media_centaur/watcher/supervisor.ex` |
| `MediaCentaur.Watcher.ConfigListener` | Subscribes to `config:updates` and routes changes to each watcher | `lib/media_centaur/watcher/config_listener.ex` |
| `MediaCentaur.Watcher.ExcludeDirs` | Pure helpers for computing effective exclude lists | `lib/media_centaur/watcher/exclude_dirs.ex` |
| `MediaCentaur.Watcher.DirMonitor` | Supervises image-dir availability monitors | `lib/media_centaur/watcher/dir_monitor.ex` |
| `MediaCentaur.Watcher.DirValidator` | Dialog-time path validation (exists / readable / not nested) | `lib/media_centaur/watcher/dir_validator.ex` |
| `MediaCentaur.Watcher.Reconciler` | Startup reconciliation against persisted state | `lib/media_centaur/watcher/reconciler.ex` |
| `MediaCentaur.Watcher.MountStatus` | Pure decision logic for the health check (device-id tracking) | `lib/media_centaur/watcher/mount_status.ex` |

> Presence storage and TTL purge moved out of `Watcher` in the library-presence-unification campaign (ADR-045). See `MediaCentaur.Library.FilePresence` and `MediaCentaur.Library.AbsenceSweeper`. The legacy `Watcher.KnownFile` / `Watcher.FilePresence` / `Watcher.AbsencePolicy` modules and the `watcher_files` table no longer exist.
