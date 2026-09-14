---
status: accepted
date: 2026-03-26
---
# Bounded context decoupling via PubSub

## Context and Problem Statement

The application began as a monolith in which Library, Pipeline, Review, Watcher, and Settings imported each other's internals: pipeline stages mutated library records, the review UI destroyed library entities directly, and changing one context meant understanding all its callers.

## Decision Outcome

Bounded contexts communicate primarily through PubSub events, and every direct cross-context dependency is declared and enforced at compile time.

1. Each context's facade module declares its dependencies in `use Boundary, deps: [...]`. That declaration is the canonical list; the Boundary compiler fails on any undeclared cross-context call. The default is no coupling, and each added dep is a deliberate, reviewable decision.
2. Cross-context communication prefers PubSub. Events carry plain data, never another context's structs. A new direct coupling defaults to PubSub unless there is a specific reason for a call. The publication idiom is [ADR-060](2026-08-06-060-event-publication-idiom.md).
3. `Settings` doubles as shared infrastructure: a context that needs per-installation persistence without justifying its own table may declare a `Settings` dep and write `Settings.Entry` rows. Settings carries no domain logic of its own.
4. `MediaCentaur.TMDB` is an adapter boundary, not a domain context; the contexts that integrate with TMDB declare it as a dep.
5. PubSub listener processes and caches do not start under `:test`; tests call public API functions directly. This keeps GenServers from touching the database after the sandbox is torn down.

### Consequences

* Cross-context work that was synchronous becomes asynchronous: a UI reacts to the resulting event rather than waiting on a return value.
* A direct dep still couples the caller to the callee's public surface; moving a function in a facade ripples to every context that declares it.
