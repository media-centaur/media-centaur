defmodule MediaCentarr.Cache do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Behaviour for context-owned caches that live in `:persistent_term`,
  ETS, or any other store the context manages.

  A cache is a write-side wiring concern: a single GenServer
  (`MediaCentarr.Cache.Worker`) that subscribes to the topics feeding
  the cache's invalidation events, recomputes the cached value at
  boot, and recomputes again whenever a relevant PubSub message
  arrives. Reads stay on the context's existing public API and
  bypass the GenServer entirely.

  ## The three flavours

  This behaviour intentionally does not constrain *where* the cached
  value lives — only that the context owns its own storage and that
  refresh is event-driven. Three storage shapes recur and each has a
  canonical use case:

  | Flavour | Use when | Examples |
  |---------|----------|----------|
  | **`:persistent_term`** | The cached value is small, hot, mostly read, rarely written. Reads are inlined into the call site at byte-code level — the cheapest read in the BEAM. Each write copies all readers' data, so reserve for tiny payloads. | `Settings`, `Capabilities`, `Controls`, `TMDB.Client` (the built `Req` client) |
  | **ETS named table** | The cached value is a result-set the LiveView renders directly (rows, structs, view-models). Reads bypass the GenServer via `:read_concurrency, true`; whole-snapshot rebuilds use `:ets.delete_all_objects` + `:ets.insert`. | `Library.Views.ContinueWatching`, `HeroCandidates`, `RecentlyAdded`, `ReleaseTracking.Views.ComingUp` |
  | **GenServer state** | The cached value is purely transient — runtime-only by nature, never persisted, no read-pressure concern. The Worker's own state holds it; reads go through `GenServer.call/2`. | `TMDB.RateLimiter` (sliding window), `Acquisition.QueueMonitor` (poll snapshot + history) |

  Misplacement is the primary defect class: durable things in
  `:persistent_term` (data lost on crash), ephemeral things in ETS
  (stale at next boot), or per-render result-sets cached as
  `:persistent_term` (write-amplification kills throughput). When in
  doubt, pick ETS — it is the safest middle ground.

  ## The PubSub pattern

  Three roles in the topic taxonomy:

    1. **Source topics** carry canonical events about the truth
       (`library:updates`, `watch_history:events`, `playback:events`,
       `release_tracking:updates`, etc.). Only the source-of-truth
       context broadcasts on these.
    2. **Cache.Worker** subscribes to the source topics it depends on
       and calls `refresh_cache/0` when `relevant?/1` accepts the
       message.
    3. **Derived topics** (`library:views`, `release_tracking:views`)
       carry `{:*_view_updated, view_id}` broadcasts emitted by
       `refresh_cache/0` after a successful rebuild. **LiveViews
       subscribe to derived topics, never to source topics for
       cache-driven data.** This is the encapsulation rule from
       ADR-041 — consumers depend on view shape, not on the source
       events that produced it.

  See `MediaCentarr.Topics` for the canonical taxonomy.

  ## Adding a new cache

  Two steps:

    1. Implement this behaviour on the context module — `subscribe/0`
       to register for the source topics that drive invalidation,
       `refresh_cache/0` to recompute and store the cached value,
       `relevant?/1` to filter incoming messages so the cache only
       refreshes when something it actually depends on changed.
       For projection caches (ETS flavour), `refresh_cache/0` should
       broadcast `{:*_view_updated, view_id}` on the derived topic
       after writing the snapshot.
    2. Register `{MediaCentarr.Cache.Worker, context: MyContext}`
       under the application supervisor.

  The Worker registers under `Module.concat(context, Cache)` by
  default, preserving the original per-cache module names without
  needing per-cache GenServer modules.

  ## Test mode

  `cache_children/1` returns `[]` in `:test` env, so no Worker is
  started during ExUnit. Tests that exercise a cache call its
  `refresh_cache/0` directly. Read functions (`Views.continue_watching/1`
  etc.) detect a missing ETS table / unset `:persistent_term` key and
  fall through to the underlying DB query — same return shape, no
  branching at the call site.
  """

  @doc """
  Subscribe the calling process to whatever PubSub topics feed this
  cache's invalidation events. Called once from the Worker's `init/1`.
  """
  @callback subscribe() :: :ok | {:error, term()}

  @doc """
  Recompute the cached value and write it to its backing store
  (`:persistent_term`, ETS, GenServer state, etc.). Called once at
  boot and again on every relevant PubSub message.
  """
  @callback refresh_cache() :: :ok

  @doc """
  True if the given PubSub message should trigger a refresh. Lets
  contexts whose subscription channel carries unrelated events (e.g.
  `Settings.subscribe/0`, which broadcasts every key change) filter
  down to the events they actually care about.
  """
  @callback relevant?(message :: term()) :: boolean()
end
