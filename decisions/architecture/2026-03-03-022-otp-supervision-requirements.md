---
status: accepted
date: 2026-03-03
---
# OTP supervision requirements

## Context and Problem Statement

The application's supervision tree grew to 17 root-level children under a flat `:one_for_one` supervisor with Erlang default restart limits (3 restarts in 5 seconds). Several structural problems emerged:

- **Stale telemetry handlers.** Both Stats GenServers capture `self()` in `:telemetry.attach_many` config. After crash-restart, the old handler remains registered with a dead PID, and the new process's `attach_many` fails silently with `{:error, :already_exists}`. The dashboard goes permanently dark.
- **No explicit restart limits.** With 17 independent children, any 3 crashing within 5 seconds terminates the entire application — plausible during disk hiccups or startup races.
- **Missing structural dependencies.** Pipeline.Stats and Pipeline are independent root children, but Pipeline depends on Stats for telemetry. Same pattern for ImagePipeline. A Stats crash should cascade to its dependent pipeline, but flat `:one_for_one` doesn't encode this.
- **FileTracker loses coverage on restart.** PubSub events during the restart window are lost, and the 24-hour TTL safety net delays cleanup.

## Decision Outcome

Chosen option: "Encode dependencies in sub-supervisors with explicit restart limits", because it confines blast radii, prevents silent telemetry breakage, and makes the supervision tree self-documenting.

### Requirements

1. **Every supervisor must set explicit `max_restarts` and `max_seconds`.** Never rely on Erlang defaults — the limits must be visible in code and tuned to the subsystem's expected failure rate.
2. **Processes with restart dependencies must be grouped under a sub-supervisor** with the appropriate strategy (`:rest_for_one` for sequential dependencies, `:one_for_all` for mutual dependencies).
3. **Telemetry handlers attached in `init/1` must detach stale handlers before re-attaching.** Call `:telemetry.detach/1` before `:telemetry.attach_many/4` to handle the crash-restart case where the old handler ID still exists.
4. **GenServers that subscribe to PubSub should use `handle_continue/2`** to run an immediate recovery check on restart, closing the gap where events may have been missed.
5. **The root supervisor remains `:one_for_one`** for independent subsystems. Sub-supervisors encode structural dependencies within subsystems.
6. **Always use `Task.Supervisor.start_child` for async work.** Never use bare `Task.start/1`. Supervised tasks are visible in the supervision tree, crashes are logged, and `Task.Supervisor` respects application shutdown ordering.

### Consequences

* Good, because crash in one pipeline subsystem no longer risks tripping the root's restart limit for unrelated children
* Good, because telemetry handlers survive Stats crash-restart without manual intervention
* Good, because the supervision tree is self-documenting — restart dependencies are visible in the code
* Good, because FileTracker recovers missed PubSub events immediately on restart instead of waiting up to 24 hours
* Bad, because two new supervisor modules add a small amount of structural code
