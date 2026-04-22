defmodule MediaCentarr.WatcherStatus do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Read-only snapshot of per-watch-dir state.

  Neutral top-level helper so modules outside the Watcher boundary
  (e.g. `MediaCentarr.Library.Availability`) can consult current state
  without creating a Boundary cycle — Library cannot directly depend on
  Watcher because Watcher already depends on Library.

  Precedent: `MediaCentarr.Topics` uses the same `check: [in: false, out: false]`
  escape hatch for cross-context PubSub topic strings.

  When Watcher's internal representation of status changes, update here.
  """

  @doc """
  Returns a list of `%{dir: path, state: atom}` for all running watchers.

  Same shape as `MediaCentarr.Watcher.Supervisor.statuses/0` — this
  module is a thin, boundary-neutral pass-through.
  """
  @spec statuses() :: [%{dir: String.t(), state: atom()}]
  defdelegate statuses(), to: MediaCentarr.Watcher.Supervisor
end
