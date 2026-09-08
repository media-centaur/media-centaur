defmodule MediaCentaur.StateProbeFormatter do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  A measurement instrument for the test-suite-determinism campaign: an
  ExUnit formatter that reports, per test, every change to the global state
  the SQL sandbox does not cover.

  After each test it snapshots the app-owned `:persistent_term` keys, the
  app's named ETS tables (size and owner), the `:media_centaur` application
  env, registered `MediaCentaur*` process names, the live children of
  `MediaCentaur.TaskSupervisor`, and the incident and console buffers. A
  test whose finish left any of those different from the previous snapshot
  gets a block in the output file: one line per changed key.

      STATE_PROBE_OUT=/tmp/state-probe.txt mix test --seed 0 \\
        --formatter ExUnit.CLIFormatter \\
        --formatter MediaCentaur.StateProbeFormatter

  Formatter events arrive by cast, so attribution is to within one test in
  the sync phase (`S` lines) and meaningless in the async phase (`A` lines),
  where tests run concurrently. Snapshots are taken after `on_exit` has run,
  so a change reported here survived whatever cleanup the test did.

  Not a fix and not a gate: it names the state a run depends on so that a
  failure can be traced to the test that wrote it, instead of to the test
  that read it (`campaigns/test-suite-determinism.md`, problem 6).
  """

  use GenServer

  @app_ets ~w(library_view_ status_view_ release_tracking_view_ integration_health pipeline_discovery_inflight)

  def init(_opts) do
    out = System.get_env("STATE_PROBE_OUT", "/tmp/state-probe.log")
    File.write!(out, "")
    snap = snapshot()
    {:ok, %{out: out, prev: snap, pristine: snap, n: 0}}
  end

  def handle_cast({:test_finished, %ExUnit.Test{} = test}, state) do
    now = snapshot()
    phase = if test.tags[:async], do: "A", else: "S"
    lines = diff(state.prev, now)

    if lines != [] do
      File.write!(
        state.out,
        "#{phase} #{state.n} #{inspect(test.module)} :: #{test.name}\n" <>
          Enum.map_join(lines, "", &("    " <> &1 <> "\n")),
        [:append]
      )
    end

    {:noreply, %{state | prev: now, n: state.n + 1}}
  end

  def handle_cast({:suite_finished, _}, state) do
    File.write!(
      state.out,
      "=== END vs pristine\n" <>
        Enum.map_join(diff(state.pristine, snapshot()), "", &("    " <> &1 <> "\n")),
      [:append]
    )

    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}

  defp snapshot do
    %{
      pt: for({k, v} <- :persistent_term.get(), ours_key?(k), into: %{}, do: {k, :erlang.phash2(v)}),
      ets:
        for(
          t <- :ets.all(),
          is_atom(t),
          app_ets?(t),
          into: %{},
          do: {t, {:ets.info(t, :size), owner(t)}}
        ),
      env:
        :media_centaur |> Application.get_all_env() |> Map.new(fn {k, v} -> {k, :erlang.phash2(v)} end),
      reg: Process.registered() |> Enum.filter(&ours_name?/1) |> Map.new(&{&1, true}),
      tasks: %{count: length(Task.Supervisor.children(MediaCentaur.TaskSupervisor))},
      buckets: %{count: safe(fn -> length(MediaCentaur.ErrorReports.list_buckets()) end)},
      console: %{count: safe(fn -> length(MediaCentaur.Console.Buffer.recent(nil)) end)}
    }
  end

  defp diff(prev, now) do
    for section <- Map.keys(now),
        line <- diff_section(section, Map.get(prev, section, %{}), Map.get(now, section, %{})),
        do: line
  end

  defp diff_section(section, prev, now) do
    added = for {k, v} <- now, not Map.has_key?(prev, k), do: "#{section} + #{inspect(k)} #{inspect(v)}"
    removed = for {k, _} <- prev, not Map.has_key?(now, k), do: "#{section} - #{inspect(k)}"

    changed =
      for {k, v} <- now,
          Map.has_key?(prev, k),
          Map.get(prev, k) != v,
          do: "#{section} ~ #{inspect(k)} #{inspect(Map.get(prev, k))} -> #{inspect(v)}"

    added ++ removed ++ changed
  end

  defp owner(table) do
    case :ets.info(table, :owner) do
      pid when is_pid(pid) ->
        case Process.info(pid, :registered_name) do
          {:registered_name, name} when is_atom(name) and name != nil -> name
          _ -> :anonymous
        end

      _ ->
        :gone
    end
  end

  defp app_ets?(t), do: Enum.any?(@app_ets, &String.starts_with?(Atom.to_string(t), &1))
  defp ours_key?({m, _}) when is_atom(m), do: ours_name?(m)
  defp ours_key?(m) when is_atom(m), do: ours_name?(m)
  defp ours_key?(_), do: false
  defp ours_name?(m), do: String.starts_with?(Atom.to_string(m), "Elixir.MediaCentaur")

  defp safe(fun) do
    fun.()
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end
end
