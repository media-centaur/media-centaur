---
status: accepted
date: 2026-03-07
---
# GenServer API encapsulation

## Context and Problem Statement

A GenServer called from other modules leaks its message protocol when callers use `GenServer.call/2` or `GenServer.cast/2` directly, coupling every call site to the message shape, the registered name, and the fact that the module is a process at all. Tests reaching for `:sys.get_state/1` as a synchronisation trick are the same leak.

## Decision Outcome

1. Never call `GenServer.call/2` or `GenServer.cast/2` from outside the module that defines the GenServer.
2. Never use `:sys.get_state/1`, `:sys.replace_state/2`, or any other `:sys.*` introspection from outside the module, tests included. MC0004 (`NoSysIntrospection`) fails any `:sys.*` call under `test/`.
3. The owning module exposes a public function for every interaction, including the synchronous trigger tests need: a scheduler or ticker exposes a `tick/0`-style function that wraps `GenServer.call(__MODULE__, :tick)`, so tests synchronise on the public API.
4. Callers use those public functions only.

### Consequences

* Each GenServer carries thin wrapper functions.
* A process with an internal `handle_info(:tick, …)` loop also implements a `handle_call(:tick, …)` clause for the test trigger.
