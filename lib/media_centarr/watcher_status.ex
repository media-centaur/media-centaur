defmodule MediaCentarr.WatcherStatus do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Boundary-neutral pass-through for `Watcher.Supervisor.statuses/0`.

  Library.Availability needs to consult per-watch-dir state on init, but
  Library cannot directly `dep:` on Watcher because Watcher already
  `dep:`s on Library (for `WatchedFile` reads in the recovery rebroadcast
  path). Adding the dep would create a Boundary cycle.

  This module is the neutral middle: it sits at the top level with
  `check: [in: false, out: false]` so any context can call it. Same
  escape-hatch pattern as `MediaCentarr.Topics` for PubSub topic strings.

  ## Future cleanup

  If the recovery rebroadcast in `MediaCentarr.Watcher` ever moves to
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
  Returns a list of `%{dir: path, state: atom}` for all running watchers.

  Same shape as `MediaCentarr.Watcher.Supervisor.statuses/0` — this
  module is a thin, boundary-neutral pass-through.
  """
  @spec statuses() :: [%{dir: String.t(), state: atom()}]
  defdelegate statuses(), to: MediaCentarr.Watcher.Supervisor
end
