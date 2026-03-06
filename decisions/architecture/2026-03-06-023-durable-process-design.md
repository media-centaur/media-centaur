---
status: accepted
date: 2026-03-06
---
# Durable process design

## Context and Problem Statement

A restart resilience audit revealed that multiple stateful processes lose in-flight work, orphan external resources, or miss events that occurred during downtime. Nine issues were identified (3 critical, 3 moderate, 3 low):

- **Watcher** re-subscribes to inotify but does not rescan the watch directories, so files added during downtime are never detected.
- **Pipeline.Producer** holds an in-memory queue of PubSub events. On restart, queued work is lost and orphaned `WatchedFile` records (files that were mid-processing) are never re-detected.
- **MpvSession** spawns an mpv process with a unique socket path. On restart, it generates a new socket path and orphans the still-running mpv process — the user's playback continues but the backend can no longer control it.
- **Debounce buffers** (FileTracker deletion debounce, batch timers) silently drop their contents on crash rather than flushing.
- **Stats counters** (Pipeline.Stats, ImagePipeline.Stats) reset to zero, losing session metrics.
- **RateLimiter** resets its token count, allowing a brief burst above the intended rate.

The root cause is a shared anti-pattern: stateful processes that hold volatile in-memory queues, timers, or external resource handles with no strategy for restart recovery. ADR-022 introduced `handle_continue/2` for PubSub recovery gaps — this ADR generalizes that pattern into a principle covering all stateful processes.

## Decision Outcome

Chosen option: "Every stateful process must be designed for restart durability", because silent data loss on restart is invisible, hard to reproduce, and compounds over time.

Every stateful process must satisfy one of two properties:

- **Resumable:** reconnects to existing external state (e.g., a still-running mpv process via a stable socket path) and picks up where it left off.
- **Idempotent restart:** re-derives its state from durable sources (database, filesystem, config) such that restarting from scratch produces the same eventual outcome as if it never stopped.

### Process classification

| Process | Current Behavior | Durable? | Required Fix |
|---------|-----------------|----------|--------------|
| Config | Reloads from TOML on every start | Yes (idempotent) | None |
| FileTracker | Runs TTL check on init, subscribes to PubSub | Yes (idempotent) | None |
| ImagePipeline.RetryScheduler | Resets retry counts; re-queries DB for pending images | Yes (idempotent) | None |
| Watcher | Re-subscribes to inotify but does not rescan | **No** | Add startup rescan |
| Pipeline.Producer | In-memory queue lost; no re-detection of orphaned files | **No** | Startup reconciliation scan |
| ImagePipeline.Producer | In-memory queue lost | Partial (RetryScheduler covers it) | Acceptable |
| MpvSession | Orphans mpv process; generates new socket path | **No** | Stable socket path + reconnect |
| Pipeline.Stats / ImagePipeline.Stats | Counters reset to zero | Acceptable (cosmetic) | None required |
| RateLimiter | Resets to zero; allows burst | Acceptable (self-correcting) | None required |

### Requirements

1. **In-memory queues must have a durable backstop.** If a process holds a queue of work items, there must be a mechanism to re-derive that queue from durable state (DB query, filesystem scan) on restart. The queue is a performance optimization, not the source of truth.

2. **External processes must be discoverable.** Any OS process spawned by the backend (mpv, ffmpeg, etc.) must use a stable, deterministic identifier (e.g., a well-known socket path or PID file) so the backend can find and reconnect to it after restart.

3. **Startup must reconcile.** Processes that watch for real-time events (inotify, PubSub) must perform a reconciliation pass on startup to detect anything that changed while they were down. This is the `handle_continue/2` pattern from ADR-022, applied broadly.

4. **Debounce buffers must flush on shutdown.** Any process holding a buffer of deferred work (deletion debounce, batch timers) must flush synchronously in `terminate/2` rather than silently dropping the buffer.

5. **Progress writes must flush on shutdown.** Any process that debounces writes to the database must persist immediately in `terminate/2`. MpvSession already does this — codify it as a requirement for all processes with deferred persistence.

### Consequences

* Good, because restart-related data loss becomes a design defect with a clear fix pattern, not an accepted risk
* Good, because the classification table gives a concrete remediation checklist for existing processes
* Good, because the requirements are composable — each process applies only the relevant subset
* Good, because it builds on ADR-022's `handle_continue/2` pattern rather than introducing a competing mechanism
* Bad, because startup reconciliation adds latency to process init (mitigated by running in `handle_continue/2`, which is non-blocking)
* Bad, because `terminate/2` flush requires `trap_exit` to be set, adding a small amount of boilerplate to affected processes
