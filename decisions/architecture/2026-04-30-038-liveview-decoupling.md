---
status: accepted
date: 2026-04-30
---
# LiveViews never couple to each other — extract shared concerns

## Context and Problem Statement

Several pages present the same objects — an entity, a play affordance, a detail modal — from separate LiveView modules. Copying a working mount clause, event handler, or template fragment from one LiveView into another is cheaper than extracting it, and the cost arrives later as silent divergence: one copy gets a fix the other does not, and each LiveView's tests cover only its own copy.

## Decision Outcome

LiveViews are leaves of the dependency graph. Behaviour or markup that two LiveViews need is extracted before the second copy is committed.

1. No LiveView imports, aliases, or calls another LiveView. A LiveView depends on contexts, components, and helper modules only.
2. Shared markup becomes a function component under `lib/media_centaur_web/components/` with typed `attr/3` declarations, rendered the same way by every caller.
3. Shared logic becomes a helper module with `async: true` unit tests, per [ADR-030](2026-04-02-030-liveview-logic-extraction.md) — `MediaCentaurWeb.LiveHelpers` and the per-component `Logic` modules are the pattern.
4. Shared mount and event wiring — the same subscriptions, the same family of `handle_info` clauses — becomes a module the LiveViews `use` (`ConsoleLive.Shared`, the `*Aware` modules under `live/`). Prefer a plain helper when the surface is small.
5. Cross-LiveView state changes flow through PubSub: a context broadcasts, each LiveView subscribes and updates its own state. No direct messages between LiveViews, in line with [ADR-029](2026-03-26-029-data-decoupling.md).
6. The second copy is the trigger. A page-specific helper may stay private until a second page needs it; extraction then happens before that page's use site lands.

### Consequences

* The first extraction costs a module name, an assigns shape, and moved tests; that is cheaper than the divergence it prevents.
* "Page-specific" versus "shared with one caller today" is a judgement; leave code in the page until a second caller appears.
