---
status: accepted
date: 2026-09-29
amended: 2026-10-03
---
# Bounded context naming

## Context and Problem Statement

Context names were chosen ad hoc. Some name the capability (`Playback`, `Acquisition`); others name a technique (`Reconciliation` names the engine's method, not its job of deciding which episode a file is). A name frames how a context is designed and read, so it needs a rule.

## Decision Outcome

1. **Name the capability, not the technique.** The name says what the context does for the product, in the domain's words.
2. **The name is the short form of a one-sentence purpose.** The `@moduledoc` opens with that sentence. A purpose that needs "and" is two contexts.
3. **Code and UI agree.** A context with a primary surface carries the surface's name.
4. **A context wrapping an external system is named for that system** (`TMDB`, `Nostr`).
5. **Names are scoped to their context.** A term only needs to be unambiguous inside its own context; the same word in two contexts is not a conflict and is never renamed for that reason.
6. **Utility modules are not bounded contexts.** `Format`, `DateUtil`, `Iso639` sit behind `Boundary` but are shared libraries; these rules do not apply to them.

First application: `Reconciliation` becomes `EpisodeMapping` — "Decides which episode on TMDB's list a file of a known series is."

Second application (2026-10-03): `Discovery` becomes `Watchlist` — "The watchlist: the title intents a person holds." Rule 3: its one surface is Incoming's Watchlist tab (UIDR-050). `Pipeline.Discovery`, file discovery, is a different context and keeps its name.

### Consequences

* Good, because a context's name tells a reader its job without opening it.
* Bad, because existing contexts that break a rule are renamed only when their context is already being changed, so the repo converges gradually.

Sources: the DDD Crew [Bounded Context Canvas](https://github.com/ddd-crew/bounded-context-canvas) (name plus a business-language purpose, agreed by the team); Vernon, *Implementing Domain-Driven Design* (names follow the ubiquitous language and are never chosen to distinguish from another context).
