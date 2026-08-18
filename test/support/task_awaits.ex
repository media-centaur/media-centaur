defmodule MediaCentaur.TaskAwaits do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Awaits context-layer background tasks so tests exit cleanly.

  Context functions like `Discovery.add_to_watchlist/1` (artwork ensure)
  and `ReleaseTracking.track_from_search_async/2` fire supervised tasks
  under the global `MediaCentaur.TaskSupervisor`. Their Req.Test stubs
  die with the owning test process, so a test that triggers one drives
  it to completion before exiting (ADR-049) — otherwise a task losing
  the race logs a "cannot find mock/stub" crash into another test's
  output.
  """

  @doc """
  Blocks until every current child of `MediaCentaur.TaskSupervisor` has
  finished (await-to-completion, never kill). Raises if any task is
  still running after 1s — that is a hang, not a timing problem.
  """
  def await_supervised_tasks do
    MediaCentaur.TaskSupervisor
    |> Task.Supervisor.children()
    |> Enum.each(fn pid ->
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      after
        1_000 -> raise "supervised task did not finish within 1s"
      end
    end)
  end
end
