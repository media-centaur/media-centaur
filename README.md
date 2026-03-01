# Media Centaur — Backend

Phoenix/Elixir application that manages the Media Centaur media library. Watches configured directories for video files, scrapes metadata and artwork from TMDB, and serves the library to the [frontend](../frontend) over Phoenix Channels (WebSocket).

- Watches directories for video files via inotify with mount resilience
- Identifies titles through TMDB search with confidence-scored auto-approval
- Downloads artwork and maps metadata to schema.org vocabulary
- Tracks playback progress through mpv with seek-aware persistence
- Serves the full library and real-time updates over WebSocket

## Contents

- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Tech Stack](#tech-stack)
- [License](#license)

## Quick Start

```bash
cp defaults/backend.toml ~/.config/media-centaur/backend.toml  # configure
mix setup          # install deps, create DB, run migrations, build assets
mix phx.server     # start dev server at http://localhost:4000
```

See [Getting Started](docs/getting-started.md) for system requirements and detailed setup.

## Documentation

| Doc | Description |
|-----|-------------|
| [Getting Started](docs/getting-started.md) | System requirements, installation, first run |
| [Configuration](docs/configuration.md) | All config options with embedded defaults |
| [Architecture](docs/architecture.md) | System overview, supervision tree, PubSub topology |
| [Watcher](docs/watcher.md) | File detection via inotify, mount resilience |
| [Pipeline](docs/pipeline.md) | Broadway processing: parse, search, fetch, download, ingest |
| [TMDB](docs/tmdb.md) | TMDB API client, confidence scoring, rate limiting |
| [Playback](docs/playback.md) | MPV integration, progress tracking, resume logic |
| [Channels](docs/channel.md) | WebSocket API for library sync and playback control |
| [Library](docs/library.md) | Ash domain, entity model, file tracking, review |

### Internal References

- [`CLAUDE.md`](CLAUDE.md) — project conventions, architecture principles, testing strategy
- [`PIPELINE.md`](PIPELINE.md) — detailed Broadway pipeline architecture
- [specifications](https://github.com/media-centaur/specifications) — cross-component contracts (API, data format, playback, images)

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Elixir ~> 1.15 |
| Web framework | Phoenix ~> 1.8 |
| Data framework | Ash ~> 3.0 |
| Database | SQLite (via AshSqlite) |
| Pipeline | Broadway ~> 1.1 |
| HTTP client | Req ~> 0.5 |
| Real-time | Phoenix Channels (WebSocket) |
| File watching | FileSystem (inotify) |
| Video playback | mpv (IPC over Unix socket) |
| CSS | Tailwind v4 + daisyUI |

## License

<!-- TODO: Add license type when LICENSE file is created -->

---

[Getting Started →](docs/getting-started.md)
