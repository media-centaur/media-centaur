# Media Centaur — Backend

Phoenix/Elixir application that manages the Media Centaur media library. Watches configured directories for video files, scrapes metadata and artwork from TMDB, and serves the library to the [frontend](../frontend) over Phoenix Channels (WebSocket).

- Watches directories for video files via inotify with mount resilience
- Identifies titles through TMDB search with confidence-scored auto-approval
- Downloads artwork and maps metadata to schema.org vocabulary
- Tracks playback progress through mpv with seek-aware persistence
- Serves the full library and real-time updates over WebSocket

Read the [documentation](docs/getting-started.md) to get started.

## Contents

- [Tech Stack](#tech-stack)
- [License](#license)

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
