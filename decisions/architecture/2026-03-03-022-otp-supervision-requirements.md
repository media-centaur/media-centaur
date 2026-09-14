---
status: accepted
date: 2026-03-03
---
# OTP supervision requirements

## Context and Problem Statement

A flat root supervisor on Erlang's default limits let three crashes in five seconds take the application down, hid restart dependencies between processes, and left stale telemetry handlers registered under a dead PID after a crash-restart.

## Decision Outcome

1. Every supervisor sets explicit `max_restarts` and `max_seconds`. Never rely on the defaults.
2. Processes with restart dependencies live under a sub-supervisor whose strategy encodes the dependency: `:rest_for_one` for sequential, `:one_for_all` for mutual.
3. The root supervisor stays `:one_for_one` for independent subsystems; sub-supervisors carry the structure.
4. A telemetry handler attached in `init/1` detaches before re-attaching, so a restart replaces the stale handler instead of failing with `:already_exists`.
5. A GenServer that subscribes to PubSub reconciles in `handle_continue/2` on start, closing the window in which events were missed. [ADR-023](2026-03-06-023-durable-process-design.md) generalises this into restart durability.
6. Async work runs under a supervisor, never bare `Task.start/1`. In the web layer the task must also be owned by the process that needs it; [ADR-049](2026-05-22-049-testing-principles.md) sets that rule.

### Consequences

* Each subsystem carries a small supervisor module of its own.
