---
status: accepted
date: 2026-05-10
---
# In-memory projections: ETS view models behind a Cache.Worker, brief eventual consistency

## Context and Problem Statement

Media Centarr is a single-user, local-only desktop application. The
traditional Phoenix concern — "every read goes through the DB so we can
horizontally scale stateless web nodes" — does not apply. Statefulness
at the BEAM level is not a liability here; it is an asset, because
runtime perceived performance is the dominant UX axis on a desktop app
that competes with Kodi, Plex, and Jellyfin.

LiveView's render model amplifies this. A page that re-runs joins,
sorts, and view-model assembly on every diff burns CPU on every
PubSub-driven re-render. With a library that grows to 5–10K entities
and views that are visited dozens of times per session, even
"sub-millisecond" DB reads accumulate into perceptible jank when a busy
pipeline run is broadcasting updates.

Three forces tug in different directions:

1. **The DB must remain the source of truth.** A crash, restart, or
   migration must be a transparent recovery — not a data-loss event.
2. **Reads must be extremely fast — microseconds, not milliseconds —
   on the hot LiveView render path.** This implies pre-shaped data in
   process memory, bypassing the DB entirely.
3. **The UI must stay easy to iterate on.** Future changes to a view's
   shape, or to how it's derived, must not ripple into every consuming
   LiveView.

The previously-shipped `MediaCentarr.Cache` behaviour
([ADR-040 lineage]) handles `:persistent_term`-backed singletons
(Settings, Capabilities, Controls, SpoilerFree). It does not yet have
an established pattern for ETS-backed read projections of
collection-shaped domain data — Library entities, watch progress
roll-ups, recently added, continue watching, recently grabbed, etc.

Without a settled pattern, every new projection becomes a one-off:
unique table layout, ad-hoc invalidation, LiveViews coupled to
source-of-truth topics, view models leaking schema shape into
templates. The long-term cost is the same shape as
[ADR-038](2026-04-30-038-liveview-decoupling.md) — silent divergence
that only surfaces as bugs.

## Decision Outcome

Chosen option: **"Each in-memory projection is a per-view ETS table
owned by a single GenServer (re-using `MediaCentarr.Cache.Worker`),
exposes a typed view-model struct as its public read contract, and
broadcasts a dedicated `library:views`-class topic so consumers
subscribe to *the projection*, not to the underlying source events."**

This pattern formalises the three-pillar separation explicitly.

### The three pillars

#### Pillar 1 — Long-term storage (the database)

The DB is the only source of truth. Every projection ultimately
rebuilds from DB state, and a cold restart is functionally
indistinguishable from a hot one (just slightly slower until the first
refresh completes).

Rules:

- Writes always hit the DB synchronously. Data integrity outranks
  perceived perf.
- No in-memory state is *authoritative* for any persistent fact. ETS
  may hold derived snapshots; the DB row is the truth.
- A projection rebuild is always re-derivable from a single query
  family. Projections that would require traversing many tables to
  rebuild are a smell — extract a smaller projection, or add a derived
  index column to make the rebuild query cheap.

#### Pillar 2 — In-memory storage (ETS)

ETS is the read fast-path. Each projection owns one named ETS table
holding **pre-shaped view-model structs**. Reads are
microsecond-scale `:ets.tab2list/1` calls — no joins, no sorts, no
schema-to-view conversion at read time.

Rules:

- One ETS table per view: `:library_view_continue_watching`,
  `:library_view_recently_added`, etc. Named (not heir-managed),
  `public`, `:read_concurrency, true`.
- Layout is whatever shape lets reads be O(1) or O(top-N): typically
  `:ordered_set` keyed by display rank with view-model values, so
  `:ets.tab2list/1` returns the list already in display order.
- Owned by a single GenServer (the projection's `Cache.Worker`
  instance). Only that process writes; everyone else reads concurrently.
- Writes happen as one `:ets.insert/2` per refresh (whole list at
  once, atomic per call). Concurrent readers see either the previous
  snapshot or the new one, never a partial state.
- Per-view (not catalog-and-views) until a second view shares
  schema-level data with the first. Premature catalog tier adds
  rebuild complexity without payoff.

#### Pillar 3 — Real-time updates (PubSub flow)

PubSub is the choreography. Source events drive projection refreshes;
projection refreshes drive UI re-reads. **The UI subscribes to the
projection, never to the source.**

```
DB write
   │
   ▼
existing source topic (library:updates, watch_history:events, …)
   │
   ├─── (bursty sources only) BroadcastCoalescer debounces
   │
   ▼
projection's Cache.Worker observes ─── refresh_cache rebuilds ETS
                                          │
                                          ▼
                              new dedicated topic broadcast
                              {:library_view_updated, :continue_watching}
                                          │
                                          ▼
                                LiveView re-reads from ETS
```

Rules:

- A projection subscribes to whichever source topics carry events
  that affect its data. Multiple subscriptions are fine — the
  projection encapsulates its own dependency set.
- Bursty sources (Pipeline runs broadcasting hundreds of
  `library:updates` per second) are coalesced via
  `Library.BroadcastCoalescer` (or an equivalent). Human-paced
  sources (`watch_history:events`) are subscribed to directly.
- After every successful refresh, the projection broadcasts
  `{:library_view_updated, view_id}` (or the analogous topic for
  non-Library projections) on its dedicated topic.
- LiveViews subscribe **only** to the projection topic, never to the
  source. This is the encapsulation that lets us change refresh
  triggers later without touching any LiveView.

### Encapsulation contract

The full surface a UI sees:

```elixir
# Subscribe (in mount/3 — never query)
Library.Views.subscribe()

# Read (in handle_params and handle_info :library_view_updated)
items = Library.Views.continue_watching(limit: 30)
# returns [%Library.Views.ContinueWatchingItem{}]

# React (in handle_info)
{:library_view_updated, :continue_watching} → re-read
```

**What can change without touching any LiveView:**

- DB schema (columns added/renamed), as long as the view module compensates
- Underlying query strategy (raw SQL vs Ecto vs preload patterns)
- ETS table shape (single table vs catalog+views)
- The set of source topics the projection subscribes to
- Coalescing strategy
- Whether the projection is hot, warm, or cold on first read

**What UI can iterate freely:**

- Add fields to the view-model struct (additive, non-breaking)
- New views — additive (new struct + new function + new ETS table +
  new Cache.Worker registration). No mutation to existing code.
- Storybook stories use a `build_*_item/1` factory — design iteration
  with no DB or PubSub dependency.

### Brief eventual consistency, by design

End-to-end latency from write to UI reflection on a typical event:

| Stage | Time |
|---|---|
| DB write commit | ~1–5 ms |
| Source broadcast | instant |
| Coalescer debounce (bursty sources only) | 50–100 ms (default) |
| Cache.Worker rebuild ETS | 1–5 ms (top-N projection) |
| `library:views` broadcast + LiveView diff | next event-loop tick |

End-to-end: 50–150 ms for coalesced sources, < 10 ms for direct
sources. Both are below human perceptual threshold. During the gap,
the LiveView shows pre-write state — never partial or corrupt state,
just a tick old.

For interactions where perceived instant feedback matters (mark
watched, etc.), LiveViews may apply optimistic updates to their own
assigns immediately; the projection refresh confirms or corrects on
arrival. This is additive — not all views need it.

### Failure modes

- **Cache.Worker crashes** → supervisor restarts → fresh subscribe +
  refresh_cache → ETS repopulated. Brief gap during init where reads
  see an empty list.
- **DB write succeeds but broadcast lost** → next coalesced event
  picks up the stale state on its way through; in extremis, next BEAM
  restart re-derives from scratch.
- **Test mode** → Cache.Worker is not started (existing pattern,
  preserved). Projection read functions fall through to direct DB
  reads when their ETS table is absent. Tests get fresh-DB semantics
  without the cache layer.
- **Projection lags real DB by N ms** → acceptable per "incredibly
  brief eventual consistency."

### Module conventions

```
MediaCentarr.Library                                — context facade
MediaCentarr.Library.Views                          — public read API + subscribe/0
MediaCentarr.Library.Views.<ViewName>Item           — typed struct (UI contract)
MediaCentarr.Library.Views.<ViewName>               — projection: implements Cache,
                                                      owns ETS table, broadcasts
                                                      on refresh
```

The same shape generalises beyond Library — `WatchHistory.Views`,
`Acquisition.Views`, etc. — when those domains earn their own
projections.

### Tests

- **Pure unit** on the view-model struct + factory (`build_*_item/1`)
- **Behaviour** on the projection (`relevant?/1` cases,
  `refresh_cache/0` populates the table correctly)
- **Equivalence** test: the new `Library.Views.X(opts)` returns the
  same data as the legacy `Library.list_X(opts)` query for
  representative fixtures. Lives until the legacy path is deleted.
- **Page smoke** (mandatory per `automated-testing` skill) for any
  new render branch the projection exposes.

## Pros and Cons

### Pros

- Reads are microseconds, not milliseconds — the LiveView re-render
  cost on a busy pipeline run drops to sub-perceptible.
- UI is decoupled from invalidation triggers. Future projection
  refresh strategy changes (incremental updates, partitioned
  rebuilds, etc.) are invisible to LiveViews.
- View-model struct is a stable contract — schema changes don't
  ripple into templates.
- Pattern is mechanical: every new projection is the same five files
  and one supervisor registration.
- DB remains the only source of truth — no risk of in-memory state
  diverging on crash.

### Cons

- Adds a layer to the request flow. A naive read used to be
  `Repo.all`; now it's `:ets.tab2list` + a projection module owning
  ETS + a Cache.Worker GenServer.
- Brief eventual consistency window means a freshly-written entity
  doesn't show up in a view for ~50–150 ms. Acceptable per the
  problem statement; flagged for the rare future case where it
  isn't (e.g. immediate post-action confirmation — handled by
  optimistic UI updates).
- Each projection is one more thing under supervision. The supervisor
  tree grows linearly with the number of views. Manageable; per-view
  cost is one GenServer + one ETS table.

## Out of Scope

- Cross-node replication. Single-user, single-node app.
- Distributed cache invalidation. Same reason.
- Persisting ETS state to disk for faster cold-start. Refresh from DB
  is fast enough; persistence adds failure modes (stale snapshot,
  corrupted file).
- Replacing Oban or Broadway with in-memory job queues. Both have
  legitimate persistence requirements.

## Lineage

- [ADR-029](2026-03-26-029-data-decoupling.md) — Boundary as the
  inter-context dependency declaration. Projection modules respect
  the same export discipline.
- [ADR-030](2026-04-02-030-liveview-logic-extraction.md) — All
  non-trivial LiveView logic must be extracted to pure functions.
  View-model struct conversion fits this contract.
- [ADR-038](2026-04-30-038-liveview-decoupling.md) — LiveViews are
  leaves; they never call into each other. Projections sit one layer
  below: shared read API for any LiveView that needs the same view.
- `MediaCentarr.Cache` behaviour — the wiring this ADR builds on.
  Applies uniformly across `:persistent_term` and ETS storage; the
  storage choice is the projection's, not the Worker's.
