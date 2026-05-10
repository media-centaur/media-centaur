defmodule MediaCentarr.Profile.MarkdownFormatter do
  @moduledoc """
  Renders a `MediaCentarr.Profile.RunData` to markdown.

  This is the human-readable counterpart of
  `MediaCentarr.Profile.JSONFormatter`. Both consume the same
  `RunData` so the two formats cannot drift.

  Sections appear in a stable order so `diff baseline.md latest.md`
  highlights real changes, not template noise. New sections must be
  appended; existing sections must not be reordered or renamed.
  """

  alias MediaCentarr.Profile.RunData

  @doc "Renders a RunData snapshot to markdown iodata."
  @spec render(%RunData{}) :: iodata()
  def render(%RunData{} = run) do
    [
      header(run.metadata),
      "\n\n",
      environment(run.metadata),
      "\n\n",
      deltas_summary(run.deltas),
      microbenchmarks(run.microbenchmarks),
      "\n\n",
      page_mounts(run.page_mounts),
      "\n\n",
      ets_memory(run.ets_memory),
      "\n\n",
      notes(),
      "\n"
    ]
  end

  @doc "Renders to a binary string."
  @spec render!(%RunData{}) :: String.t()
  def render!(%RunData{} = run), do: run |> render() |> IO.iodata_to_binary()

  # ---- Sections -----------------------------------------------------------

  defp header(meta) do
    """
    # Media Centarr Profile Run

    | key | value |
    |-----|-------|
    | run_id | `#{meta.run_id}` |
    | timestamp | #{meta.timestamp} |
    | scale | `#{meta.scale}` |
    | git sha | `#{meta.git_sha}` |
    | git branch | `#{meta.git_branch}` |
    | dirty? | #{meta.dirty} |
    | OTP | #{meta.otp_release} |
    | Elixir | #{meta.elixir_version} |
    """
  end

  defp environment(meta) do
    """
    ## Environment

    | key | value |
    |-----|-------|
    | schedulers_online | #{meta.schedulers_online} |
    | total schedulers | #{meta.cpu_count} |
    | database_path | `#{meta.database_path}` |
    """
  end

  defp deltas_summary(nil), do: ""

  defp deltas_summary(%{compared_against: against, summary: summary} = deltas) do
    summary_table = """
    ## Deltas vs `#{against.run_id}` (sha `#{against.git_sha}`)

    | classification | count |
    |---|---:|
    | REGRESSION (>+#{Float.round(deltas.thresholds.big * 1.0, 1)}%) | #{Map.get(summary, :REGRESSION, 0)} |
    | regression (>+#{Float.round(deltas.thresholds.stable * 1.0, 1)}%) | #{Map.get(summary, :regression, 0)} |
    | stable | #{Map.get(summary, :stable, 0)} |
    | improvement (<-#{Float.round(deltas.thresholds.stable * 1.0, 1)}%) | #{Map.get(summary, :improvement, 0)} |
    | IMPROVEMENT (<-#{Float.round(deltas.thresholds.big * 1.0, 1)}%) | #{Map.get(summary, :IMPROVEMENT, 0)} |
    | new (no baseline value) | #{Map.get(summary, :new, 0)} |
    | **total** | **#{Map.get(summary, :total, 0)}** |
    """

    flagged = Enum.reject(deltas.metrics, &(&1.classification in [:stable, :new]))

    case flagged do
      [] ->
        summary_table <> "\n_No metrics outside threshold._\n\n"

      _ ->
        rows = Enum.map_join(flagged, "\n", &flagged_row/1)

        summary_table <>
          """

          ### Flagged metrics

          | classification | metric | current | baseline | Δ |
          |---|---|---:|---:|---:|
          #{rows}

          """
    end
  end

  defp flagged_row(metric) do
    label = metric_label(metric)
    classification = Atom.to_string(metric.classification)

    "| #{classification} | #{label} | #{format_metric_value(metric.metric, metric.current)} " <>
      "| #{format_metric_value(metric.metric, metric.baseline)} | #{format_delta_pct(metric.delta_pct)} |"
  end

  defp metric_label(%{
         category: :microbenchmark,
         suite: suite,
         input: input,
         scenario: scenario,
         metric: m
       }) do
    "#{suite} / #{input} / #{scenario} (#{m})"
  end

  defp metric_label(%{category: :page_mount, route: route, metric: m}) do
    "mount `#{route}` (#{m})"
  end

  defp metric_label(%{category: :ets_memory, table: table, metric: m}) do
    "ETS `:#{table}` (#{m})"
  end

  defp microbenchmarks([]), do: "## Microbenchmarks\n\n_(no suites discovered)_"

  defp microbenchmarks(results) do
    sections = Enum.map(results, &suite_section/1)
    Enum.join(["## Microbenchmarks" | sections], "\n\n")
  end

  defp suite_section(%{suite: name, runs: runs}) do
    rows =
      Enum.flat_map(runs, fn %{input: input, scenarios: scenarios} ->
        Enum.map(scenarios, fn scenario -> scenario_row(input, scenario) end)
      end)

    table_header = "| Input | Scenario | ips | avg | p50 | p99 | min | memory |"
    table_div = "|---|---|---:|---:|---:|---:|---:|---:|"

    Enum.join(["### #{name}", "", table_header, table_div | rows], "\n")
  end

  defp scenario_row(input, %{name: name, stats: stats, memory: memory}) do
    "| #{input} | #{name} | #{format_ips(stats.ips)} | #{format_time(stats.average_ns)} " <>
      "| #{format_time(stats.median_ns)} | #{format_time(stats.p99_ns)} " <>
      "| #{format_time(stats.min_ns)} | #{format_memory(memory)} |"
  end

  defp page_mounts([]), do: "## Page Mount Timing\n\n_(no routes measured)_"

  defp page_mounts(results) do
    rows =
      Enum.map(results, fn r ->
        "| `#{r.route}` | #{r.warm_cache} | #{r.runs} | " <>
          "#{format_us(r.min_us)} | #{format_us(r.p50_us)} | " <>
          "#{format_us(r.p95_us)} | #{format_us(r.max_us)} |"
      end)

    Enum.join(
      [
        "## Page Mount Timing (Phoenix.LiveViewTest)",
        "",
        "| Route | Warm cache? | runs | min | p50 | p95 | max |",
        "|---|---|---:|---:|---:|---:|---:|" | rows
      ],
      "\n"
    )
  end

  defp ets_memory([]) do
    "## ETS Memory\n\n_(no projection tables present — Cache.Workers may not have started)_"
  end

  defp ets_memory(rows) do
    table_rows =
      Enum.map(rows, fn r ->
        "| `:#{r.table}` | #{r.rows} | #{Float.round(r.bytes / 1024, 1)} |"
      end)

    Enum.join(
      ["## ETS Memory", "", "| Table | Size (rows) | Memory (KB) |", "|---|---:|---:|" | table_rows],
      "\n"
    )
  end

  defp notes do
    """
    ## Notes

      * No concurrent Pipeline / Watcher activity during the run.
      * Per-scenario warmup applied (Benchee `warmup: 2`s; mount
        harness 5× warmup + 30× timed).
      * Benchee memory metric measures the calling process and
        includes Benchee's own allocations; treat as relative-only.
      * Sample sizes are floors — bump in `Profile.Mounts.@runs`
        and `Profile.Bench.@benchee_opts[:time]` if results show
        bimodal distributions.
      * Protocol consolidation is disabled in `MIX_ENV=dev`; absolute
        timings are slightly inflated, ratios are unaffected.
      * See `decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md`
        for the design these measurements validate.
    """
  end

  # ---- Formatters ----

  defp format_ips(ips) when is_number(ips) do
    cond do
      ips >= 1_000_000 -> "#{Float.round(ips / 1_000_000, 2)} M"
      ips >= 1000 -> "#{Float.round(ips / 1000, 2)} K"
      true -> "#{Float.round(ips * 1.0, 2)}"
    end
  end

  defp format_ips(_), do: "—"

  defp format_time(ns) when is_number(ns) do
    cond do
      ns < 1000 -> "#{Float.round(ns * 1.0, 2)} ns"
      ns < 1_000_000 -> "#{Float.round(ns / 1000, 2)} µs"
      ns < 1_000_000_000 -> "#{Float.round(ns / 1_000_000, 2)} ms"
      true -> "#{Float.round(ns / 1_000_000_000, 2)} s"
    end
  end

  defp format_time(_), do: "—"

  defp format_us(us) when is_number(us) do
    cond do
      us < 1000 -> "#{us} µs"
      us < 1_000_000 -> "#{Float.round(us / 1000, 2)} ms"
      true -> "#{Float.round(us / 1_000_000, 2)} s"
    end
  end

  defp format_us(_), do: "—"

  defp format_memory(nil), do: "—"
  defp format_memory(0), do: "0 B"

  defp format_memory(bytes) when is_number(bytes) do
    cond do
      bytes < 1024 -> "#{trunc(bytes)} B"
      bytes < 1_048_576 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{Float.round(bytes / 1_048_576, 2)} MB"
    end
  end

  defp format_metric_value(metric_name, value) when is_number(value) do
    cond do
      String.ends_with?(Atom.to_string(metric_name), "_ns") -> format_time(value)
      String.ends_with?(Atom.to_string(metric_name), "_us") -> format_us(value)
      metric_name == :bytes -> format_memory(value)
      true -> "#{value}"
    end
  end

  defp format_metric_value(_metric_name, nil), do: "—"

  defp format_delta_pct(pct) when is_number(pct) do
    sign = if pct >= 0, do: "+", else: ""
    "#{sign}#{Float.round(pct, 1)}%"
  end

  defp format_delta_pct(_), do: "—"
end
