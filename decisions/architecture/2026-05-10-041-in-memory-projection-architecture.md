---
status: accepted
date: 2026-05-10
---
# In-memory projections: ETS view models behind a Cache.Worker, brief eventual consistency

## Context and Problem Statement

Media Centaur is a single-user desktop app, so statefulness on the BEAM is an asset: perceived render speed matters more than stateless web nodes. A LiveView that re-runs joins and view-model assembly on every PubSub-driven diff burns CPU exactly when a pipeline run is broadcasting. The database must stay the source of truth, hot reads must be microseconds, and a view's shape must be changeable without touching every LiveView that consumes it.

## Decision Outcome

Each in-memory projection is a per-view ETS table owned by a single `MediaCentaur.Cache.Worker`, exposes a typed view-model struct as its read contract, and broadcasts on its own `*:views` topic so consumers subscribe to the projection, never to the source events. Three pillars:

1. **Long-term storage.** The database is the only source of truth. Writes hit it synchronously; no ETS state is authoritative for any persistent fact; every projection rebuilds from one query family, and a cold restart differs from a hot one only in the first refresh.
2. **In-memory storage.** One named, public, `read_concurrency` ETS table per view, holding pre-shaped view-model structs in display order so a read is `:ets.tab2list/1`. Only the owning worker writes, as one whole-list insert per refresh, so readers see the old snapshot or the new one, never a partial state.
3. **Real-time updates.** The projection subscribes to whichever source topics affect its data (bursty sources through `Library.BroadcastCoalescer`), rebuilds, then broadcasts `{:library_view_updated, view}` on `library:views`. LiveViews subscribe only to that topic.

The consumer contract is `Library.Views.subscribe/0` in `mount/3`, a read such as `Library.Views.continue_watching/1` in `handle_params/3` and on `{:library_view_updated, _}`, and nothing else. Query strategy, table shape, source topics and coalescing may change without touching a LiveView; new views and new struct fields are additive. Other domains follow the same shape when they earn a projection.

Consistency is eventual and brief (tens of milliseconds); a LiveView may apply an optimistic assign and let the refresh confirm it. In `:test` no worker starts and projection reads fall through to the database.

### Consequences

* A naive read used to be one `Repo` call; it is now a projection module, an ETS table and a supervised worker per view, and the supervision tree grows one worker per view.
* A freshly written row is invisible to a view until its refresh lands; a surface that needs instant confirmation owns an optimistic assign.
