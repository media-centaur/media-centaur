---
status: accepted
date: 2026-03-07
amended: 2026-04-25
---
# This app is the sole writer to entity records and image storage

## Context and Problem Statement

Multiple processes (Pipeline workers, LiveView event handlers, Oban jobs, the Watcher, future replicas or sync agents) can plausibly want to mutate library records or write images on disk. Without a clear ownership rule, concurrent writers race on the same entity row or image file, producing inconsistent state, half-written files, and silent overwrites.

Earlier framings of this ADR predicated the rule on a backend (Phoenix/Elixir) vs. frontend (Rust) split. The Rust frontend has been retired; this app is now the only component. The single-writer invariant still matters for the same reasons, just not for the same reason.

## Decision Outcome

**This Phoenix application is the sole writer to entity records (DB) and image storage (filesystem under `data/images/`).** Every mutation goes through a context module that owns the resource (`Library`, `Pipeline`, `Review`, etc.), serializes through Ecto, and broadcasts a PubSub event after the write.

1. **Only this app writes to the `images/` directory.** Reads (HTTP serving, browser image fetches) are unrestricted, but creating, modifying, or deleting image files is an operation owned by the context that owns the entity.
2. **Only this app mutates entity records.** External integrations (TMDB, Prowlarr) are read-only sources. User actions arrive as LiveView events, Oban jobs, or PubSub messages and are translated into context calls — never direct DB writes from the source.
3. **The pipeline is a mediator, not a side effect.** Pipeline stages call context functions to write; they do not bypass the context layer to insert records or write files directly.

### Consequences

* Good, because there is exactly one process model responsible for filesystem and database integrity
* Good, because every mutation has a discoverable code path that ends in a context function
* Good, because the PubSub broadcast contract (ADR-011) has a single point of enforcement
* Bad, because a future replicated or distributed deployment must extend this rule rather than disclaim it — adding a second writer is a major architectural change, not a configuration tweak
