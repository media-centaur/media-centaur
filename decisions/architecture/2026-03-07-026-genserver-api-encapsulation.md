---
status: accepted
date: 2026-03-07
---
# GenServer API encapsulation

## Context and Problem Statement

Several GenServers in this application (Watcher, Config, MpvSession) are called from multiple modules. When callers use `GenServer.call/2` or `GenServer.cast/2` directly, the message protocol leaks across module boundaries. This couples callers to the message format, the registered name, and the fact that the module is a GenServer at all. Refactoring the process requires updating every call site.

The same coupling shows up in tests when production code reaches for OTP introspection (`:sys.get_state/1`, `:sys.replace_state/2`) — historically tolerated in this repo as a "synchronisation barrier" trick (`send(pid, :tick); :sys.get_state(pid)` to flush the mailbox). It is the same protocol leak in different clothing, and it ties tests to whatever happens to be in the GenServer's state at the moment.

## Decision Outcome

Chosen option: "Wrap all GenServer interactions in public functions on the owning module", because the module boundary should encapsulate the process protocol.

1. **Never call `GenServer.call/2` or `GenServer.cast/2` from outside the module** that defines the GenServer.
2. **Never use `:sys.get_state/1`, `:sys.replace_state/2`, or any other `:sys.*` introspection** from outside the module — including from tests. This was previously allowed as a test sync trick; it no longer is.
3. **Expose a public function API** on the module that wraps the call or cast internally — including any synchronous "trigger" the tests need. For schedulers and tickers, this typically means a public `tick/0`-style function that does `GenServer.call(__MODULE__, :tick)` so tests synchronise against the public API rather than peeking at process state. Example: `MediaCentarr.ImagePipeline.RetryScheduler.tick/1`.
4. **Callers use the module's public functions**, not the GenServer protocol directly.

These rules are enforced by `MediaCentarr.Credo.Checks.NoSysIntrospection` (bans `:sys.*` in `test/`) and surfaced by code review for direct `GenServer.call/cast` in callers.

### Consequences

* Good, because the GenServer's message format is an internal implementation detail
* Good, because the process can be refactored (renamed, split, replaced with ETS) without changing callers
* Good, because the public API can validate arguments and provide documentation
* Good, because tests no longer fail when an unrelated state field is added or renamed
* Bad, because each GenServer needs thin wrapper functions that may feel like boilerplate
* Bad, because GenServers with internal `handle_info(:tick, ...)` loops must also implement a parallel `handle_call(:tick, ...)` clause to give tests a synchronous trigger point
