# System Components

Media Centaur is built from two primary components: a **backend** (Elixir/Phoenix) that owns all data and playback logic, and a **frontend** (Rust/GPUI) that acts as a thin rendering client. They communicate over a **WebSocket connection** using Phoenix Channels.

---

## Component Overview

| Component | Role |
|-----------|------|
| `backend` (backend) | Authoritative service: media library, metadata scraping, MPV playback lifecycle, watch progress, resume logic |
| `frontend` (client) | Rendering client: displays library, sends play commands, shows playback progress |

---

## Backend (backend)

**Repository:** `media-centaur/media-centaur`

The backend is the **single source of truth** for the entire system. It manages the media library, controls MPV playback, tracks watch progress, and exposes all data and commands over a Phoenix Channels WebSocket API.

### Responsibilities

- Maintain the canonical media library in SQLite (entities, metadata, images, seasons, episodes)
- Watch `media_dir` for new video files and run the automated detection/scraping pipeline
- Serve the media library to the UI over Phoenix Channels on connect
- Manage MPV playback instances (launch, monitor, stop) via JSON IPC over Unix domain sockets
- Track watch progress per episode/movie (position, duration, timestamps)
- Implement resume logic: given "play series X", determine the correct episode and position
- Push real-time updates to the UI: library changes, playback state, entity progress updates
- Provide a local admin panel (Phoenix LiveView) for manual review and library management

### Technology

- Language: Elixir
- Framework: Phoenix + LiveView (admin), Phoenix Channels (UI API)
- Database: SQLite via Ash + ash_sqlite
- Pipeline: Broadway
- MPV control: JSON IPC over Unix domain sockets, managed by GenServer-per-instance
- HTTP client: Req

---

## User-Interface (client)

**Repository:** `media-centaur/frontend`

A Rust/GPUI native desktop application designed for fullscreen 10-foot UI with remote or gamepad input. It connects to the backend on startup and operates as a rendering client — all data comes from the backend, all commands go to the backend.

### Responsibilities

- Connect to the backend via WebSocket (Phoenix Channels) on startup
- Receive and display the media library (grid of cards, detail views, season/episode navigation)
- Send play commands to the backend (e.g. "play series X" — the backend determines the episode)
- Display watch progress indicators on cards and in detail views
- Show playback state (playing, paused, stopped) received from the backend
- Display connection status when the backend is unavailable
- Handle reconnection gracefully

### Backend Required

The UI requires a running backend. If the backend is unavailable, the UI starts with an empty library and shows a connection status screen until the backend connects. There is no offline mode or file-based fallback — the backend is the single source of truth.

### Technology

- Language: Rust
- UI framework: GPUI (Community Edition fork)
- UI components: gpui-component
- Display: Native Wayland, Vulkan GPU acceleration
- WebSocket: tungstenite (or equivalent async WebSocket client)
- Async: smol

---

## Communication: Phoenix Channels (WebSocket)

The UI and backend communicate over a single WebSocket connection using the Phoenix Channels protocol. Bidirectional, multiplexed, with built-in heartbeat and automatic reconnection.

### High-Level Contract

| Direction | Examples |
|-----------|---------|
| Backend → UI | Full library on join, library updates (entity added/removed/changed), playback state changes, entity progress updates |
| UI → Backend | Play commands (entity ID, optional episode), pause, stop, seek |

See [`API.md`](API.md) for the full message schema and channel specification.

---

## Shared Data Paths

Image files are stored on disk by the backend and referenced by absolute filesystem path in entity data pushed over the WebSocket. The backend resolves paths at serialization time — the UI receives ready-to-use absolute paths and never needs a base directory.

Format details are in `IMAGE-CACHING.md`.

---

## Integration Contract

### Primary: WebSocket API (Phoenix Channels)

1. The UI connects to the backend on startup and joins the relevant channels.
2. The backend sends the full library state on channel join.
3. Library mutations (new entities, metadata updates, removals) are pushed as incremental updates.
4. Play commands flow from UI to backend; the backend manages MPV and pushes playback state back.
5. Watch progress is tracked by the backend and pushed to the UI for display.

See [`API.md`](API.md) for the complete specification.

### Secondary: File System (images)

1. Image files exist at absolute paths specified in entity data (`contentUrl` fields). The backend resolves paths at push time.
2. Entity `@id` values are stable UUIDs — they double as image directory names and must never be reassigned.
3. The UI handles missing images gracefully (placeholder rendering).

See [`IMAGE-CACHING.md`](IMAGE-CACHING.md) for directory conventions and role definitions.

---

## Testing

Both components have automated test suites that verify the WebSocket API contract from each side:

- **Backend channel tests** verify that join replies and PubSub-driven pushes produce string-keyed JSON matching API.md after serialization.
- **Frontend dispatch tests** verify that the dispatcher correctly classifies realistic API.md-format messages into typed events.

Both sides test against the same contract. If either side's wire format drifts, its tests fail.

See [`TESTING.md`](TESTING.md) for manual testing procedures.
