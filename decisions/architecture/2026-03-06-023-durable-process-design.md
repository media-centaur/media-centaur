---
status: accepted
date: 2026-03-06
amended: 2026-09-12
---
# Durable process design

## Context and Problem Statement

A restart-resilience audit found stateful processes that lost in-flight work, dropped debounce buffers, or missed events that arrived while they were down: the Watcher re-subscribed to inotify without rescanning, the pipeline producer held its queue in memory, deferred writes were discarded on crash. The shared cause was volatile in-memory state with no restart strategy.

## Decision Outcome

Every stateful process satisfies one of two properties:

* **Resumable** — it reconnects to existing external state (a running mpv process via a stable socket path) and continues.
* **Idempotent restart** — it re-derives its state from durable sources (database, filesystem, config), so restarting from scratch reaches the same outcome as never stopping.

Requirements:

1. An in-memory queue has a durable backstop: it can be rebuilt from a database query or a filesystem scan. The queue is an optimisation, not the source of truth.
2. An OS process spawned by the application (mpv, ffmpeg) uses a stable, deterministic identifier — a well-known socket path or PID file — so the application can find it again after a restart.
3. A process that watches real-time events (inotify, PubSub) reconciles on startup, in `handle_continue/2`, to catch what changed while it was down.
4. A debounce buffer flushes synchronously in `terminate/2` rather than dropping its contents.
5. A process that defers database writes persists them in `terminate/2`. This needs `trap_exit`.

**Amendment 2026-09-12.** This record originally claimed that a restart orphaned a still-playing mpv, which `MediaCentaur.Playback.SessionRecovery` would reconnect to. That premise was never true on the development machine: the dev unit shipped `KillMode=mixed`, so every restart killed the whole cgroup, mpv included, and the recovery path never fired. Measured 2026-09-12, mpv survives a restart under `KillMode=process`, which both units now ship. The resumable design of `MediaCentaur.Playback.MpvSession` stands; only the factual claim was wrong.

### Consequences

* Startup reconciliation adds latency to process init; running it in `handle_continue/2` keeps `init/1` non-blocking.
* Flush-on-terminate requires `trap_exit` in every process with deferred persistence.
