---
status: accepted
date: 2026-05-29
---
# Desktop LiveViews load on first paint; never flash fabricated values

## Context and Problem Statement

Every top-level LiveView deferred its data load until the WebSocket
connected, via an `ensure_loaded/1` helper gated by
`connected?(socket) and not socket.assigns.loaded?`. This was codified in
AGENTS.md as an "Iron Law: no DB queries in `mount/3`", justified by *"doubled
queries scale linearly with traffic"*.

That justification is a **web-app** concern. Media Centaur is a single-user
**desktop** app reading **local** SQLite + ETS — there is no traffic, and the
"doubled query" is one user's millisecond. Meanwhile the gate caused a real,
user-visible bug: the static HTTP render (the first thing painted) ran with the
mount placeholders, so every page flashed fabricated values — `0 titles · 0
movies · 0 shows`, empty grids, empty lists — until the socket connected and
re-rendered with real data. UIDR-012 already commits this app to *"render
correctly the first time"*; the gate violated that everywhere.

Four pages had additionally pushed their (still local) loads onto
`start_async/3` to satisfy a "no blocking LV page loads" rule — another
web-latency concern that produced the same flash, since async work cannot run
on the disconnected render at all.

## Decision Outcome

Chosen option: **load synchronously on the first render**, because the loads
are local and bounded, so a correct first paint costs a single user a few
milliseconds — a trade UIDR-012 already endorses.

- `ensure_loaded/1` is gated **only** by `not socket.assigns.loaded?` — never
  by `connected?`. The load runs in `handle_params/3` on both the disconnected
  and connected renders.
- Subscriptions stay in `mount/3` inside `if connected?(socket)` (unchanged).
- The four pages that used `start_async/3` for their initial load
  (`watch_history`, `upcoming`, `review`, `acquisition`) now load inline; their
  `handle_async(:*_load)` clauses were removed. Genuinely networked async stays
  async (e.g. `settings`' update-check).
- **First paint must never show a fabricated value.** If a load is genuinely
  slow (network, or a query that scales past a few ms locally), defer it with an
  owned `start_async/3` (ADR-049) and render an honest **loading skeleton** —
  never a zero/empty mistakable for real data.

This supersedes the web-framed "Iron Law: no DB queries in `mount/3`" and the
"no blocking LV page loads" rule for local loads. Each converted `ensure_loaded`
carries a comment warning against re-adding the `connected?` gate, and a
disconnected-render (`get/2`) regression test per page locks the behaviour in.

`status_live` still loads its operational stats via `start_async` (storage and
directory-health probes touch the filesystem and are the one plausible
skeleton candidate); it is the documented place to apply the skeleton exception
if its first paint proves to flash.

### Consequences

* Good, because the first paint is correct on every page — no empty-state flash,
  honouring UIDR-012's desktop-rendering contract.
* Good, because removing the cargo-culted async indirection makes the load path
  simpler and easier to reason about.
* Bad, because a full page load / cross-page navigation now runs the local
  queries inline; on a pathologically large local dataset this could become
  perceptible, at which point that specific page upgrades to the skeleton
  exception. Relates to [UIDR-012](../user-interface/2026-05-20-012-desktop-app-rendering-defaults.md) and
  [ADR-049](2026-05-22-049-testing-principles.md).
