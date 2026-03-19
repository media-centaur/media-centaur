<div align="center">

<!-- TODO: Add logo/banner image -->
<!-- ![Media Centaur](docs/images/banner.png) -->

# Media Centaur

**A self-hosted media center for Linux that watches your library, identifies your media, and gets out of the way.**

[![License: TBD](https://img.shields.io/badge/license-TBD-blue)](#license)
[![Elixir](https://img.shields.io/badge/Elixir-1.15+-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org)
[![Platform](https://img.shields.io/badge/platform-Linux-informational?logo=linux&logoColor=white)](https://kernel.org)

Point it at your video directories. It identifies your movies and TV shows via TMDB, downloads artwork, tracks your progress, and plays everything through mpv — all from a real-time LiveView interface designed for the living room.

Zero-config SQLite database. No Docker. No transcoding server. No accounts.

</div>

---

<!-- TODO: Full-width screenshot of the Library page (dark mode, Continue Watching + poster grid) -->
<!-- ![Media Centaur Library](docs/images/screenshot-library.png) -->
<!-- *The Library — Continue Watching cards and poster grid* -->

---

## Why Media Centaur

**Built for the living room.** This is a 10-foot interface designed to drive a TV connected to a Linux PC. You navigate with a keyboard or gamepad from the couch — not a phone app, not a web dashboard you squint at. Spatial navigation, large artwork, and focus-driven interaction make it feel like a console media app, not a web page.

**mpv is the player.** Media Centaur doesn't reinvent video playback. mpv is the best video player on Linux — hardware decoding, format support, subtitle handling, shader pipelines, HDR passthrough. Media Centaur integrates with mpv over IPC so you get all of its capabilities with none of the file-management overhead.

**Your files, your machine.** Single-user, single-machine. No accounts, no auth, no cloud, no Docker, no transcoding server. Point it at your video directories and it handles the rest. SQLite means zero database administration — the entire library is one file you can back up with `cp`.

**Automatic but not magic.** It watches your directories, identifies your media via TMDB, and downloads artwork — all automatically. But when the confidence is low, it queues the file for human review instead of guessing wrong. You stay in control.

**Real-time, not refresh.** Every state change — new file detected, metadata fetched, artwork downloaded, playback started — propagates instantly to the UI via PubSub. No polling, no stale pages, no manual refresh. The interface feels alive because it is.

---

## Features

### 📁 Library Management

- Watches directories for video files via inotify with automatic mount/unmount resilience
- Supports movies, TV series (with seasons and episodes), collections, and extras/bonus features
- Smart filename parser handles release-group naming conventions, nested directories, and edge cases
- Configurable extras directories (`Extras/`, `Featurettes/`, `Behind The Scenes/`, etc.) linked to parent movies
- Exclude and skip directories to ignore samples, incomplete downloads, or system folders
- Graceful handling of removable and network drives — files on disconnected drives are retained for a configurable period

### 🎬 Metadata & Artwork

- TMDB search with confidence-scored auto-approval — high-confidence matches are written automatically
- Low-confidence matches are queued for human review with an inline TMDB search panel
- Downloads poster, backdrop, logo, and thumbnail artwork per entity
- Resizes images to WebP for efficient storage and fast rendering
- Maps all metadata to schema.org vocabulary (JSON-LD compatible)
- Per-entity artwork stored alongside your media or in a configurable cache directory

### ▶️ Playback

- mpv integration via JSON IPC — full control without leaving the interface
- Seek-aware progress tracking with a 20-second minimum threshold (ignores scrubbing)
- Smart resume: picks up where you left off for movies, advances to the next episode for TV series
- 90% completion threshold marks episodes/movies as watched
- Per-entity playback sessions with live progress updates in the UI

### ⚡ Processing Pipeline

- Built on [Broadway](https://github.com/dashbitco/broadway) for supervised, fault-tolerant processing
- Five stages: Parse → Search → FetchMetadata → DownloadImages → Ingest
- 15 concurrent processors, partitioned by file path to prevent conflicts
- Idempotent and race-safe — duplicate detections, concurrent processing of the same TMDB ID, and re-scans are all handled gracefully
- Review-resolved files re-enter the pipeline automatically, skipping the search stage
- Batch PubSub broadcasts minimize UI update overhead

### 🖥️ Real-Time Interface

- Phoenix LiveView — server-rendered, real-time UI with no JavaScript framework and no page reloads
- PubSub-driven updates: every entity change, pipeline event, and playback state change is pushed instantly
- Keyboard and gamepad navigation with spatial focus — designed for couch use
- Dark-first design with light mode support, system theme detection, and manual toggle
- Collapsible glassmorphism sidebar, poster grids, backdrop hero sections, and detail modals

### 🔧 Observability & Control

- Per-component debug logging (`:watcher`, `:pipeline`, `:tmdb`, `:playback`, `:library`) toggleable from the UI or IEx
- Pipeline stats: throughput, error counts, active processors, per-stage timing
- Storage measurement across watch directories, image caches, and the database file
- Service start/stop, directory scanning, and cache management from the Settings page
- Named BEAM node with remote IEx shell access for live debugging

---

## Pages

### Library

<!-- TODO: Screenshot of Library page with Continue Watching and poster grid -->
<!-- ![Library](docs/images/screenshot-library-full.png) -->

The default landing page. Two zones:

- **Continue Watching** — backdrop cards for in-progress media with resume labels and progress bars
- **Library Browse** — poster grid with type tabs (All / Movies / TV), sort (Recently Added / A–Z / Year), and text filter
- **Detail Modal** — hero section with backdrop and logo, metadata, description, season/episode tree for TV, movie list for collections, file info, TMDB rematch, and delete controls
- Scrollable episode lists with a pinned header so entity identity stays visible

### Dashboard

<!-- TODO: Screenshot of Dashboard page -->
<!-- ![Dashboard](docs/images/screenshot-dashboard.png) -->

The operational hub — everything you need at a glance:

- Library stats: movie, series, collection, episode, and file counts
- Pipeline status: per-stage throughput, errors, active count, and scan trigger
- Watcher health per directory with state indicators
- TMDB rate limiter status and configuration
- Recent errors table (last 50)
- Storage metrics: disk usage per watch directory, image cache, and database
- Playback and review summary cards

### Review

<!-- TODO: Screenshot of Review page -->
<!-- ![Review](docs/images/screenshot-review.png) -->

Triage queue for low-confidence TMDB matches:

- Side-by-side comparison of parsed filename info vs. TMDB result with images and descriptions
- Inline TMDB search for manual matching
- Approve, dismiss, or re-search — resolved files re-enter the pipeline automatically
- Files grouped by series root for efficient batch review

### Settings

<!-- TODO: Screenshot of Settings page -->
<!-- ![Settings](docs/images/screenshot-settings.png) -->

- Per-component logging toggles with framework log suppression
- Read-only configuration reference showing all active settings
- Danger zone: scan directories, clear database, clear and refresh image cache

---

## Getting Started

### Requirements

| Dependency | Version | Notes |
|------------|---------|-------|
| Erlang/OTP | 26+ | Required by Elixir 1.15+ |
| Elixir | ~> 1.15 | With Mix build tool |
| SQLite3 | 3.x | Database engine |
| mpv | any | Video playback |
| inotify-tools | any | File system watching (Linux) |

You'll also need a free [TMDB API key](https://www.themoviedb.org/settings/api).

### Install

```bash
git clone https://github.com/media-centaur/media-centaur.git
cd media-centaur/backend
mix setup
```

### Configure

```bash
mkdir -p ~/.config/media-centaur
cp defaults/backend.toml ~/.config/media-centaur/backend.toml
```

Edit `~/.config/media-centaur/backend.toml` — at minimum, set your watch directories and TMDB API key:

```toml
watch_dirs = [
  { dir = "/path/to/your/videos" },
]

[tmdb]
api_key = "your-tmdb-api-key"
```

See [Configuration](docs/configuration.md) for all options.

### Run

```bash
mix phx.server
```

Open [http://localhost:4001](http://localhost:4001).

---

## Configuration

Media Centaur is configured via a TOML file at `~/.config/media-centaur/backend.toml`. All keys have sensible defaults — see `defaults/backend.toml` for the full reference.

| Section | Key Options | Description |
|---------|-------------|-------------|
| *(top-level)* | `watch_dirs`, `exclude_dirs`, `database_path`, `file_absence_ttl_days` | Watch directories, exclusions, database location, retention for disconnected drives |
| `[tmdb]` | `api_key` | TMDB API credentials |
| `[pipeline]` | `auto_approve_threshold`, `extras_dirs`, `skip_dirs` | Confidence threshold, extras directory names, skip directory names |
| `[playback]` | `mpv_path`, `socket_dir`, `socket_timeout_ms` | mpv binary path, IPC socket location and timeout |
| `[dashboard]` | `recent_changes_days`, `recently_watched_count` | Dashboard display preferences |

---

## Running as a Service

### Development

```bash
scripts/install-dev                                    # install systemd user service
systemctl --user start media-centaur-backend-dev       # start
journalctl --user -u media-centaur-backend-dev -f      # logs
```

Connect a REPL to the running server:

```bash
iex --name repl@127.0.0.1 --remsh media_centaur_dev@127.0.0.1
```

Disconnect with `Ctrl+\` — the server keeps running.

### Production

```bash
scripts/release    # build production release
scripts/install    # install to ~/.local/lib/media-centaur/ and set up systemd
```

The release binds to `127.0.0.1:4000`, runs migrations automatically, and manages its own systemd user unit. See [Getting Started — Release](docs/getting-started.md#release) for full details.

---

## Tech Stack

| Component | Technology | Why |
|-----------|------------|-----|
| Language | [Elixir](https://elixir-lang.org) | Fault-tolerant concurrency, hot code reloading, pattern matching |
| Web framework | [Phoenix LiveView](https://github.com/phoenixframework/phoenix_live_view) | Real-time server-rendered UI without a JS framework |
| Data framework | [Ash](https://ash-hq.org) | Declarative resources, actions, and authorization |
| Database | [SQLite](https://sqlite.org) | Zero-admin embedded database, single-file backups |
| Pipeline | [Broadway](https://github.com/dashbitco/broadway) | Supervised concurrent processing with backpressure |
| Video player | [mpv](https://mpv.io) | Best-in-class Linux video playback via JSON IPC |
| CSS | [Tailwind v4](https://tailwindcss.com) + [daisyUI](https://daisyui.com) | Utility-first styling with semantic component classes |
| Metadata | [TMDB](https://www.themoviedb.org) | Comprehensive movie and TV metadata API |
| HTTP client | [Req](https://github.com/wojtekmach/req) | Composable HTTP client with built-in retry and test support |

---

## Architecture

```
                        ┌──────────────────────────────────────────────────┐
                        │                 TMDB API                         │
                        └──────────┬───────────────┬───────────────┬───────┘
                                   │ search        │ metadata      │ images
                                   │               │               │
 ┌─────────────┐    ┌─────────────────────────────────────────────────────────┐
 │             │    │                    Broadway Pipeline                     │
 │  Video      │    │                                                         │
 │  Files      │    │  ┌───────┐   ┌────────┐   ┌──────────┐   ┌──────────┐  │
 │             │    │  │ Parse ├──▸│ Search ├──▸│  Fetch   ├──▸│ Download ├──┐│
 │  /movies/   │    │  └───────┘   └────┬───┘   │ Metadata │   │  Images  │  ││
 │  /tv/       │    │                   │       └──────────┘   └──────────┘  ││
 │  /extras/   │    │              low  │                              │      │
 │             │    │           confidence                             │      │
 └──────┬──────┘    │                   │       ┌──────────┐   ┌──────▾──┐   │
        │           │                   └──────▸│  Review  │   │  Ingest │   │
   inotify          │                           │  Queue   ├──▸│         │   │
        │           │                           └──────────┘   └────┬────┘   │
 ┌──────▾──────┐    └───────────────────────────────────────────────│────────┘
 │   Watcher   │                                                    │
 │  Supervisor ├──── PubSub ──▸ Producer                            │ PubSub
 │             │                                                    │
 │  per-dir    │    ┌───────────────────────────────────────────────▾────────┐
 │  watchers   │    │                  Phoenix LiveView                      │
 └─────────────┘    │                                                        │
                    │  Dashboard    Library    Review    Settings             │
 ┌─────────────┐    │  stats/health  browse    triage    logging             │
 │   SQLite    │◂───│  pipeline      playback  search    services            │
 │             │    │  storage       progress  approve   config              │
 └─────────────┘    │                   │                                    │
                    └───────────────────│────────────────────────────────────┘
 ┌─────────────┐                       │
 │ Image Cache │                  ┌────▾────┐
 │  WebP       │                  │   mpv   │
 │  per-entity │                  │   IPC   │
 └─────────────┘                  └─────────┘
```

---

## Documentation

Detailed documentation lives in the [`docs/`](docs/) directory:

- [Getting Started](docs/getting-started.md) — installation, configuration, running, and release
- [Configuration](docs/configuration.md) — all config options with defaults
- [Architecture](docs/architecture.md) — system overview and component relationships
- [Pipeline](docs/pipeline.md) — how files are processed from detection to library
- [Watcher](docs/watcher.md) — directory watching, mount resilience, and scanning
- [TMDB](docs/tmdb.md) — metadata scraping, confidence scoring, and rate limiting
- [Playback](docs/playback.md) — mpv integration, progress tracking, and resume logic
- [Library](docs/library.md) — entity model, serialization, and browsing
- [Input System](docs/input-system.md) — keyboard and gamepad navigation
- [mpv](docs/mpv.md) — mpv IPC protocol and configuration

---

## License

<!-- TODO: Choose and add license -->

TBD

---

## Acknowledgments

<a href="https://www.themoviedb.org">
  <img src="https://www.themoviedb.org/assets/2/v4/logos/v2/blue_short-8e7b30f73a4020692ccca9c88bafe5dcb6f8a62a4c6bc55cd9ba82bb2cd95f6c.svg" alt="TMDB" width="120">
</a>

This product uses the TMDB API but is not endorsed or certified by TMDB.

Built with [Elixir](https://elixir-lang.org), [Phoenix](https://phoenixframework.org), [Ash](https://ash-hq.org), [Broadway](https://github.com/dashbitco/broadway), and [mpv](https://mpv.io).
