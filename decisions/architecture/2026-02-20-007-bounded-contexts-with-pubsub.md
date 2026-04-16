---
status: superseded
date: 2026-02-20
superseded-by: decisions/architecture/2026-03-26-029-data-decoupling.md
---
# Bounded contexts communicating through PubSub

> **Superseded by ADR-029** — see `decisions/architecture/2026-03-26-029-data-decoupling.md` for the current bounded context rules, context table, and acceptable-reads policy.

## Context and Problem Statement

The application has multiple functional areas — library management, pipeline processing, playback, file watching, review, configuration, and the web layer. Without clear boundaries, these areas tend to reach into each other's internals, creating tight coupling where a change in one subsystem requires understanding and modifying several others.

## Decision Outcome

Chosen option: "bounded contexts with PubSub-only cross-context communication", because it enforces low coupling at the architecture level. Each context owns its own data and behavior; cross-context interaction happens exclusively through PubSub events.

**Context boundaries:**
- Library (entities, files, images, identifiers, seasons, episodes, settings)
- Pipeline (Broadway processing, stages, producer)
- Playback (MPV session, resume algorithm, progress tracking)
- Watcher (inotify file detection, directory scanning)
- Review (pending files, UI intake)
- Config (TOML loading, XDG paths)
- Web (channels, LiveViews, router)

**Communication rules:**
- Contexts never call into another context's internal modules
- All cross-context interaction uses `Phoenix.PubSub` broadcasts
- Ash changes are intrinsic only — they must not orchestrate external integrations, call APIs, or cross context boundaries
- The pipeline is a mediator: it actively orchestrates by calling services and handing results to the library, but domain resources never trigger pipeline behavior through state changes

### Consequences

* Good, because modifying one context does not require analyzing blast radius on unrelated contexts
* Good, because PubSub events create a clear, auditable integration surface
* Good, because contexts can be tested in isolation with PubSub stubs
* Bad, because PubSub events are fire-and-forget — debugging cross-context flows requires correlating events across subscribers
