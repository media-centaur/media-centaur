---
status: accepted
date: 2026-05-29
---
# Desktop LiveViews load on first paint; never flash fabricated values

## Context and Problem Statement

Every top-level LiveView deferred its data load until the socket connected, a web-app rule that does not apply to a single-user desktop app reading local SQLite and ETS. The static first render painted placeholders (zero counts, empty grids) until the connected render replaced them, violating [UIDR-012](../user-interface/2026-05-20-012-desktop-app-rendering-defaults.md).

## Decision Outcome

1. **Local loads run synchronously on the first render.** `ensure_loaded/1` is gated only by `not socket.assigns.loaded?`, never by `connected?/1`, and runs in `handle_params/3` on both renders. Each site carries a comment against re-adding the gate and a disconnected-render regression test.
2. **Subscriptions stay in `mount/3`** inside `if connected?(socket)`.
3. **Genuinely slow loads stay async**: network calls, or a query past a few milliseconds locally, through owned `start_async/3` ([ADR-049](2026-05-22-049-testing-principles.md)) with an honest loading skeleton.
4. **First paint never shows a fabricated value.** A zero or an empty list that could be mistaken for data is a bug.

This supersedes the "no DB queries in `mount/3`" and "no blocking page loads" rules for local loads. The Status page, once the skeleton candidate, now loads inline like every other page.

### Consequences

* A page whose local dataset grows past a few milliseconds upgrades to the skeleton exception individually.
