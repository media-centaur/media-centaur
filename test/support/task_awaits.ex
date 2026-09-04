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

  @await_ms 1_000

  @doc """
  Blocks until `MediaCentaur.TaskSupervisor` has no children left
  (await-to-completion, never kill). Tasks a task starts on its way out —
  release tracking's artwork download follows its `track_from_search`
  task — are picked up on the next pass, so the supervisor is empty when
  this returns. Raises if anything is still running after 1s — that is a
  hang, not a timing problem.
  """
  def await_supervised_tasks, do: drain(System.monotonic_time(:millisecond) + @await_ms)

  defp drain(deadline) do
    case Task.Supervisor.children(MediaCentaur.TaskSupervisor) do
      [] ->
        :ok

      pids ->
        Enum.each(pids, &await_down(&1, deadline))
        drain(deadline)
    end
  end

  defp await_down(pid, deadline) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        raise "supervised task did not finish within #{@await_ms}ms"
    end
  end
end
