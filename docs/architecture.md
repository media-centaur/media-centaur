# Architecture

Media Centaur Backend is a Phoenix/Elixir application that watches directories for video files, enriches them with TMDB metadata and artwork, and serves the library to a Rust frontend over WebSocket.

## System Overview

```mermaid
graph TB
    subgraph Frontend["Frontend (Rust)"]
        UI[UI Application]
    end

    subgraph Backend["Backend (Elixir/Phoenix)"]
        WS[Phoenix Channels<br/>WebSocket /socket]

        subgraph Core["Core Subsystems"]
            Watcher[Watcher<br/>inotify per directory]
            Pipeline[Broadway Pipeline<br/>15 concurrent processors]
            TMDB[TMDB Client<br/>rate-limited]
            Library[Library<br/>Ash domain + SQLite]
            Playback[Playback<br/>MPV IPC]
            Review[Review<br/>pending files]
        end

        PubSub[Phoenix PubSub]
    end

    subgraph External
        TMDBAPI[TMDB API]
        FS[File System<br/>inotify]
        MPV[mpv player]
    end

    UI <-->|WebSocket| WS
    WS <--> PubSub
    Watcher --> PubSub
    PubSub --> Pipeline
    Pipeline --> TMDB
    TMDB --> TMDBAPI
    Pipeline --> Library
    Watcher --> FS
    Playback --> MPV
    Library --> PubSub
    Review --> PubSub
```

## Data Flow

```mermaid
flowchart LR
    A[File System] -->|inotify| B[Watcher]
    B -->|PubSub: file_detected| C[Pipeline]
    C -->|Parse| D[Parser]
    C -->|Search| E[TMDB]
    C -->|FetchMetadata| E
    C -->|DownloadImages| F[TMDB CDN]
    C -->|Ingest| G[Library]
    G -->|PubSub: entities_changed| H[Channel]
    H -->|WebSocket push| I[Frontend]

    J[Review UI] -->|PubSub: review_resolved| C
```

## Supervision Tree

```mermaid
graph TD
    App[MediaCentaur.Supervisor<br/>one_for_one]

    App --> Telemetry[Telemetry]
    App --> Repo[Repo<br/>SQLite]
    App --> LogInit[Log Init Task]
    App --> PubSub[Phoenix.PubSub]
    App --> TaskSup[TaskSupervisor]
    App --> RateLimiter[TMDB.RateLimiter]
    App --> WatcherSup[Watcher.Supervisor<br/>one_for_all]
    App --> WatcherStart[Watcher Start Task]
    App --> Stats[Pipeline.Stats]
    App --> Pipeline[Pipeline<br/>Broadway]
    App --> FileTracker[FileTracker]
    App --> PlaybackSup[Playback.Supervisor<br/>rest_for_one]
    App --> Endpoint[Phoenix Endpoint]

    WatcherSup --> Registry[Watcher.Registry]
    WatcherSup --> DynSup[DynamicSupervisor]
    DynSup --> W1[Watcher /dir1]
    DynSup --> W2[Watcher /dir2]

    PlaybackSup --> SessionSup[SessionSupervisor<br/>DynamicSupervisor]
    PlaybackSup --> Manager[Manager]
    SessionSup --> MpvSession[MpvSession]
```

Children start in order. Watcher and Pipeline are conditionally disabled in test environment.

## PubSub Topics

All inter-component communication flows through Phoenix PubSub:

| Topic | Events | Publishers | Subscribers |
|-------|--------|------------|-------------|
| `pipeline:input` | `file_detected`, `review_resolved` | Watcher, Review UI | Pipeline Producer |
| `library:updates` | `entities_changed` | Pipeline batcher, FileTracker | LibraryChannel |
| `library:file_events` | `files_removed` | Watcher | FileTracker |
| `watcher:state` | `watcher_state_changed` | Watcher | FileTracker |
| `playback:events` | `playback_state_changed`, `entity_progress_updated` | MpvSession | PlaybackChannel, Manager |
| `review:updates` | `file_reviewed` | Pipeline | Review LiveView |

## Key Principles

- **Ash is the only data interface.** All reads and writes go through Ash actions — no raw SQL, no `Ecto.Query`, no `Repo` calls.
- **Schema.org vocabulary.** Entity fields use schema.org property names.
- **UUIDs are permanent.** Entity IDs never change once assigned.
- **PubSub for cross-context communication.** Contexts don't call into each other's internals.
- **Pipeline is a mediator.** The pipeline actively orchestrates — domain resources don't trigger pipeline behavior.

## Specifications

Cross-component contracts live in `../specifications/`:

| Spec | Governs |
|------|---------|
| [API.md](../../specifications/API.md) | Phoenix Channels WebSocket protocol |
| [DATA-FORMAT.md](../../specifications/DATA-FORMAT.md) | JSON-LD entity serialization format |
| [IMAGE-CACHING.md](../../specifications/IMAGE-CACHING.md) | Image storage conventions |
| [PLAYBACK.md](../../specifications/PLAYBACK.md) | MPV integration and progress tracking |
| [COMPONENTS.md](../../specifications/COMPONENTS.md) | System component architecture |

## Module Reference

| Module | Description | Path |
|--------|-------------|------|
| `MediaCentaur.Application` | OTP application, supervision tree | `lib/media_centaur/application.ex` |
| `MediaCentaur.Config` | TOML config loader | `lib/media_centaur/config.ex` |
| `MediaCentaur.Log` | Component-level thinking logs | `lib/media_centaur/log.ex` |
| `MediaCentaur.Serializer` | Entity to JSON-LD serializer | `lib/media_centaur/serializer.ex` |
| `MediaCentaur.Storage` | Disk usage measurement | `lib/media_centaur/storage.ex` |
| `MediaCentaur.Admin` | Destructive admin operations | `lib/media_centaur/admin.ex` |
| `MediaCentaur.Dashboard` | Dashboard data fetching | `lib/media_centaur/dashboard.ex` |
