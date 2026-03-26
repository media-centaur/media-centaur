---
status: accepted
date: 2026-03-26
---
# Bounded context decoupling via PubSub

## Context and Problem Statement

The backend started as a monolith where Library, Pipeline, Review, Watcher, and Settings modules freely imported each other's internals. This created a web of compile-time dependencies: changing one context required understanding all its callers, pipeline stages directly mutated library records, and the Review UI reached into Library to destroy entities.

The goal was to isolate each context behind a clear boundary so that changes within a context don't ripple across the codebase.

## Decision Outcome

Chosen option: "Five bounded contexts communicating only via PubSub events", because it matches OTP's message-passing model, requires no new infrastructure, and makes the data flow between contexts explicit and traceable.

### The five contexts

| Context | Table prefix | Responsibility |
|---------|-------------|----------------|
| Library | `library_` | Entities, images, identifiers, watched files, watch/extra progress |
| Pipeline | `pipeline_` | Discovery, Import, and Image pipelines; image queue |
| Review | `review_` | PendingFile lifecycle for human review |
| Watcher | `watcher_` | File detection, mount resilience, file presence tracking |
| Settings | `settings_` | Runtime configuration entries |

### Rules

1. **No context aliases another context's modules.** Each context has its own `Inbound`/`Intake` GenServer (or equivalent) that subscribes to PubSub topics and delegates to internal functions.
2. **Cross-context communication uses PubSub events only.** Events carry plain data (maps, lists, atoms) — never structs from another context.
3. **Acceptable reads:** Pipeline and Watcher may query `library_watched_files` directly (via `Repo` + `Ecto.Query`, not through `Library` context functions) for dedup/presence checks. This avoids coupling while allowing efficient lookups.
4. **Consumer modules are exempt.** Dashboard, Admin, Playback, Serializer, and ImagePipeline are consumers of Library data, not bounded contexts. They may read Library freely.
5. **PubSub listener GenServers don't start in test mode.** Tests call public API functions directly. This avoids sandbox race conditions where GenServers process PubSub messages after the test sandbox is torn down.

### Consequences

* Good, because each context can be understood, tested, and modified independently
* Good, because the PubSub event flow is explicit — `Topics.ex` centralizes all topic strings
* Good, because new consumers can subscribe without modifying the producer
* Bad, because rematch became async (fire-and-forget broadcast instead of synchronous call) — the UI must react to incoming events rather than waiting for a result
* Bad, because acceptable reads (dedup queries) still couple Pipeline/Watcher to Library's table schema, just not its module API
