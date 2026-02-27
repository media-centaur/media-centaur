---
status: accepted
date: 2026-02-21
---
# Phoenix Channels as the UI integration point

## Context and Problem Statement

The `user-interface` app (a separate Rust/GPUI application) needs to receive the full media library, get real-time updates when entities change, and send playback commands. The original approach used a shared `media.json` file on disk, which required file watching, had no push capability, and created race conditions between reads and writes.

## Considered Options

* Phoenix Channels over WebSocket
* Shared `media.json` file on disk
* REST API with polling

## Decision Outcome

Chosen option: "Phoenix Channels over WebSocket", because it provides bidirectional, real-time communication without filesystem coupling. The backend pushes entity data on join and streams updates as they happen; the UI sends playback commands back over the same connection.

**Channel topology:**
- `library` channel: full library on join, batched entity pushes on change, entity removal notifications
- `playback` channel: play/pause/stop commands from UI, progress updates from backend

**Batching rule:** All entity pushes must be chunked by the channel's `@batch_size`. Bulk operations can touch every entity in the library — an unbounded push would overwhelm the WebSocket.

### Consequences

* Good, because updates are instant — no polling delay or file-watch latency
* Good, because the connection is bidirectional — playback commands use the same socket
* Good, because the backend controls serialization format — no risk of the UI reading a partially-written file
* Good, because every contract between backend and UI is documented in `../specifications/`
* Bad, because the UI must maintain a WebSocket connection — offline/disconnected state requires handling
