defmodule MediaCentaur.WatcherStatus do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Boundary-neutral pass-through for `Watcher.Supervisor.statuses/0`.

  Library.Availability needs to consult per-media-dir state on init, but
  Library cannot directly `dep:` on Watcher because Watcher already
  `dep:`s on Library (for `WatchedFile` reads in the recovery rebroadcast
  path). Adding the dep would create a Boundary cycle.

  This module is the neutral middle: it sits at the top level with
  `check: [in: false, out: false]` so any context can call it. Same
  escape-hatch pattern as `MediaCentaur.Topics` for PubSub topic strings.

  ## Future cleanup

  If the recovery rebroadcast in `MediaCentaur.Watcher` ever moves to
  Library (e.g. by having Library subscribe to a watcher event and load
  its own data), Watcher would no longer need Library as a dep, the
  cycle would dissolve, and this module could be deleted. Until then,
  it is the only file Library can read live watcher state from.

  ## When changing Watcher's status vocabulary

  `Watcher.Supervisor.statuses/0` returns internal vocabulary
  (`:watching | :initializing | :unavailable`); broadcasts use
  (`:available | :unavailable`). `Library.Availability.init/1`
  normalises the snapshot to broadcast vocabulary so downstream code
  sees one set of values. Keep that in mind when adding new states here.
  """

  @doc """
  Returns a list of per-watcher status maps for all running watchers.

  Same shape as `MediaCentaur.Watcher.Supervisor.statuses/0` — this
  module is a thin, boundary-neutral pass-through. Only `dir` and `state`
  are load-bearing for `Library.Availability`; the additional keys
  (`reason`, `settling_count`, `pending_deletions`) carry the Status
  page's activity narrative and are ignored here.
  """
  @spec statuses() :: [
          %{
            dir: String.t(),
            state: atom(),
            reason: atom() | nil,
            settling_count: non_neg_integer(),
            pending_deletions: non_neg_integer()
          }
        ]
  defdelegate statuses(), to: MediaCentaur.Watcher.Supervisor
end
