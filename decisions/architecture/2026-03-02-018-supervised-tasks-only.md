---
status: accepted
date: 2026-03-02
---
# Always use Task.Supervisor for async work

## Context and Problem Statement

The codebase uses `Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, ...)` for fire-and-forget async work in most places (Watcher, OperationsLive, MpvSession), but ReviewLive used bare `Task.start/1`. Unsupervised tasks are invisible to the supervision tree — if they crash, no one notices, and they cannot be monitored or shut down gracefully during application stop.

## Decision Outcome

Chosen option: "Always use `Task.Supervisor.start_child`", because it keeps all async work under the supervision tree where crashes are visible, tasks are trackable, and graceful shutdown works correctly.

### Consequences

* Good, because all async work is visible in the supervision tree and crashes are logged
* Good, because `Task.Supervisor` respects application shutdown ordering
* Bad, because slightly more verbose than bare `Task.start` — acceptable trade-off
