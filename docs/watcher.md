# Watcher

The watcher subsystem monitors configured directories for video file additions and removals using Linux inotify. One `Watcher` GenServer runs per directory, coordinated by a shared supervisor.

> [Getting Started](getting-started.md) · [Configuration](configuration.md) · [Architecture](architecture.md) · **Watcher** · [Pipeline](pipeline.md) · [TMDB](tmdb.md) · [Playback](playback.md) · [Library](library.md)

- [Architecture](#architecture)
- [Key Concepts](#key-concepts)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [PubSub Events](#pubsub-events)
- [Module Reference](#module-reference)

## Architecture

```mermaid
graph TD
    Config[Config.get :watch_dirs] --> Sup

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

- `watch_dirs` — directories to monitor (see [configuration.md](configuration.md))
- `exclude_dirs` — directories to skip (absolute paths)

Each watcher also auto-excludes its own images directory and staging directory.

## How It Works

### File Detection

1. inotify reports a create/modify event for a file with a video extension
2. Watcher starts size stability polling (2 checks, 5 seconds apart)
3. Once stable, broadcasts `{:file_detected, %{path, watch_dir}}` to `"pipeline:input"`
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
2. If directory becomes accessible again, state transitions to `:watching`
3. Auto-scan runs to detect any files added while the directory was unavailable
4. State change broadcast to `"watcher:state"` PubSub topic

### Manual Scan

The dashboard provides a "Scan directories" button that calls `Watcher.Supervisor.scan/0`. This walks all watched directories recursively, detecting video files not yet tracked in the database. Each new file enters the pipeline normally.

## PubSub Events

| Topic | Event | Payload |
|-------|-------|---------|
| `pipeline:input` | `:file_detected` | `%{path: string, watch_dir: string}` |
| `library:file_events` | `:files_removed` | `[path, ...]` |
| `watcher:state` | `:watcher_state_changed` | `{dir, new_state}` |

## Module Reference

| Module | Description | Path |
|--------|-------------|------|
| `MediaCentarr.Watcher` | Per-directory GenServer, inotify + PubSub | `lib/media_centarr/watcher.ex` |
| `MediaCentarr.Watcher.Supervisor` | Coordinates all watchers, scan/pause API | `lib/media_centarr/watcher/supervisor.ex` |
