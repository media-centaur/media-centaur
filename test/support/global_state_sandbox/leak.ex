defmodule MediaCentaur.GlobalStateSandbox.Leak do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Raised by `MediaCentaur.GlobalStateSandbox` when global state is off the
  baseline at an edge: at check-in, for the verified stores the test left
  behind; at checkout, for anything the async phase left behind. The leak
  has already been restored or contained when this is raised — the error
  exists so the failure lands on the test that made the leak, not on the
  test that would have read it.
  """

  defexception [:phase, :leaks]

  @type t :: %__MODULE__{
          phase: :checkout | :checkin,
          leaks: [MediaCentaur.GlobalStateSandbox.Snapshot.leak()]
        }

  @impl true
  def message(%__MODULE__{phase: :checkin, leaks: leaks}) do
    """
    This test left global state the harness cannot put back:

    #{lines(leaks)}
    The leak has been contained so the next test starts clean; fix this test.
    A test drives its own async work to completion and stops what it starts
    (ADR-049). See `MediaCentaur.GlobalStateSandbox`.
    """
  end

  def message(%__MODULE__{phase: :checkout, leaks: leaks}) do
    """
    Global state was already off the baseline when this test began:

    #{lines(leaks)}
    Every sync test checks the machine back in clean, so this was left by
    the async phase: an async test wrote global state it does not own.
    The baseline has been restored; this test fails so the leak is not
    silent. See `MediaCentaur.GlobalStateSandbox`.
    """
  end

  defp lines(leaks), do: Enum.map_join(leaks, "\n", &("    " <> line(&1))) <> "\n"

  defp line({:persistent_term, key, from, to}),
    do: ":persistent_term #{inspect(key)}: #{change(from, to)}"

  defp line({:application_env, key, from, to}),
    do: "application env #{inspect(key)}: #{change(from, to)}"

  defp line({:registered, name, _from, _to}),
    do: "process #{inspect(name)} is still registered and alive"

  defp line({:ets, table, from, to}),
    do: "ETS table #{inspect(table)} owned by an app process: #{change(from, to)}"

  defp line({:tasks, pids, _from, _to}),
    do: "#{length(pids)} child(ren) of MediaCentaur.TaskSupervisor still running"

  defp line({:stub_orphans, messages, _from, _to}),
    do: "a process made a request no Req.Test stub could answer: " <> Enum.join(messages, "; ")

  defp line({:probe, id, from, to}), do: "#{inspect(id)} reads #{inspect(to)}, baseline #{inspect(from)}"

  defp change(:absent, to), do: "added #{inspect(to, limit: 8)}"
  defp change(_from, :absent), do: "erased"
  defp change(from, to), do: "#{inspect(from, limit: 8)} -> #{inspect(to, limit: 8)}"
end
