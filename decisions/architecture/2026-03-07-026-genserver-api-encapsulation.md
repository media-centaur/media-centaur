---
status: accepted
date: 2026-03-07
---
# GenServer API encapsulation

## Context and Problem Statement

Several GenServers in this application (Watcher, Config, MpvSession, PlaybackManager) are called from multiple modules. When callers use `GenServer.call/2` or `GenServer.cast/2` directly, the message protocol leaks across module boundaries. This couples callers to the message format, the registered name, and the fact that the module is a GenServer at all. Refactoring the process requires updating every call site.

## Decision Outcome

Chosen option: "Wrap all GenServer interactions in public functions on the owning module", because the module boundary should encapsulate the process protocol.

1. **Never call `GenServer.call/2` or `GenServer.cast/2` from outside the module** that defines the GenServer.
2. **Expose a public function API** on the module that wraps the call or cast internally.
3. **Callers use the module's public functions**, not the GenServer protocol directly.

### Consequences

* Good, because the GenServer's message format is an internal implementation detail
* Good, because the process can be refactored (renamed, split, replaced with ETS) without changing callers
* Good, because the public API can validate arguments and provide documentation
* Bad, because each GenServer needs thin wrapper functions that may feel like boilerplate
