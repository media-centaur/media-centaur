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

  Adding a new cache is two steps:

    1. Implement this behaviour on the context module — `subscribe/0`
       to register for the topic that drives invalidation,
       `refresh_cache/0` to recompute and store the cached value,
       `relevant?/1` to filter incoming messages so the cache only
       refreshes when something it actually depends on changed.
    2. Register `{MediaCentarr.Cache.Worker, context: MyContext}`
       under the application supervisor.

  The Worker registers under `Module.concat(context, Cache)` by
  default, preserving the original per-cache module names without
  needing per-cache GenServer modules.
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
