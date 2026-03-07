---
status: accepted
date: 2026-03-07
---
# Backend owns all writes to shared storage

## Context and Problem Statement

The system has two main components — a backend (Phoenix/Elixir) and a frontend (Rust) — that share access to entity data and image files on the filesystem. Without a clear ownership boundary, both sides could write to shared directories, creating race conditions, stale data, and unclear responsibility for cleanup and integrity.

## Decision Outcome

Chosen option: "The backend is the sole writer to shared storage", because a single-writer model eliminates write conflicts and makes the backend the authoritative source for all persistent state.

1. **Only the backend writes to the `images/` directory.** The frontend reads images for display but never creates, modifies, or deletes them.
2. **Only the backend creates and mutates entity records.** The frontend receives entity data over Phoenix Channels and renders it.
3. **The frontend sends commands, not mutations.** Playback requests, review decisions, and other user actions are sent as channel messages — the backend decides what state changes result.

### Consequences

* Good, because there is exactly one process responsible for filesystem and database integrity
* Good, because the frontend can be stateless with respect to persistent data — it only caches what the backend pushes
* Bad, because all write paths must go through the backend, adding latency for operations that could theoretically be done locally
