defmodule MediaCentarr.Profile.Reporter do
  @moduledoc """
  Markdown writer for profile runs (ADR-041).

  Produces `priv/profiling/runs/<ISO8601>.md` and a `latest.md`
  symlink pointing at the most recent run. Sections appear in a
  stable order — `diff baseline.md latest.md` is meaningful only
  if the schema doesn't drift, so changes here should be additive
  (append a new section) rather than rearranging existing ones.

  ## Sections

    1. Header — run metadata (id, timestamp, git sha, branch,
       dirty?, OTP/Elixir versions, scale, schedulers, db path).
    2. Microbenchmarks — one subsection per `Profile.Suite`.
    3. Page Mount Timing — per-route timings from `Profile.Mounts`.
    4. ETS Memory — sizes of every `:library_view_*` projection
       table (auto-discovered).
    5. Notes — confounds (no concurrent Pipeline activity, JIT
       warmup applied, Benchee memory metric is relative-only).
  """

  alias MediaCentarr.Profile

  @runs_dir "priv/profiling/runs"

  @doc """
  Writes a run report. Returns the absolute path of the report file.

  Also rewrites `<runs_dir>/latest.md` as a symlink to the new file
  so anyone running `cat priv/profiling/runs/latest.md` gets the
  freshest run without needing to know the timestamp.

  ## Options

    * `:runs_dir` — output directory. Defaults to
      `priv/profiling/runs`. Tests pass an absolute tmp dir so
      they don't write into the repo or rely on cwd (which would
      break async tests).
  """
  @spec write(map(), [map()], [map()], keyword()) :: Path.t()
  def write(metadata, bench_results, mount_results, opts \\ []) do
    runs_dir = Keyword.get(opts, :runs_dir, @runs_dir)
    File.mkdir_p!(runs_dir)

    filename = "#{metadata.run_id}.md"
    path = Path.join(runs_dir, filename)

    body =
      Enum.join(
        [
          header(metadata),
          environment(metadata),
          microbenchmarks(bench_results),
          page_mounts(mount_results),
          ets_memory(),
          notes()
        ],
        "\n\n"
      )

    File.write!(path, body <> "\n")
    update_latest_symlink(path, runs_dir)

    Path.expand(path)
  end

  defp header(meta) do
    """
    # Media Centarr Profile Run

    | key | value |
    |-----|-------|
    | run_id | `#{meta.run_id}` |
    | timestamp | #{DateTime.to_iso8601(meta.timestamp)} |
    | scale | `#{meta.scale}` |
    | git sha | `#{meta.git_sha}` |
    | git branch | `#{meta.git_branch}` |
    | dirty? | #{meta.dirty?} |
    | OTP | #{meta.otp_release} |
    | Elixir | #{meta.elixir_version} |
    """
  end

  defp environment(meta) do
    """
    ## Environment

    | key | value |
    |-----|-------|
    | schedulers_online | #{meta.schedulers} |
    | total schedulers | #{meta.cpu_count} |
    | database_path | `#{meta.database_path}` |
    """
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
        "| `#{r.route}` | #{r.warm_cache?} | #{r.runs} | " <>
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

  defp ets_memory do
    rows =
      :ets.all()
      |> Enum.filter(&projection_table?/1)
      |> Enum.sort_by(&table_name/1)
      |> Enum.map(&ets_row/1)

    case rows do
      [] ->
        "## ETS Memory\n\n_(no projection tables present — Cache.Workers may not have started)_"

      _ ->
        Enum.join(
          ["## ETS Memory", "", "| Table | Size (rows) | Memory (KB) |", "|---|---:|---:|" | rows],
          "\n"
        )
    end
  end

  defp projection_table?(table) do
    case :ets.info(table, :name) do
      :undefined ->
        false

      name when is_atom(name) ->
        name_str = Atom.to_string(name)
        String.contains?(name_str, "_view_") or String.starts_with?(name_str, "library_view_")

      _ ->
        false
    end
  end

  defp table_name(table) do
    case :ets.info(table, :name) do
      :undefined -> ""
      name -> Atom.to_string(name)
    end
  end

  defp ets_row(table) do
    name = table_name(table)
    size = :ets.info(table, :size)
    words = :ets.info(table, :memory)
    bytes = words * :erlang.system_info(:wordsize)
    "| `:#{name}` | #{size} | #{Float.round(bytes / 1024, 1)} |"
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
      * See `decisions/architecture/2026-05-10-041-in-memory-projection-architecture.md`
        for the design these measurements validate.
    """
  end

  defp update_latest_symlink(path, runs_dir) do
    latest = Path.join(runs_dir, "latest.md")
    _ = File.rm(latest)
    target = Path.basename(path)
    File.ln_s(target, latest)
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

  @doc false
  def runs_dir, do: @runs_dir

  @doc false
  # Acts as a touch-point so the alias keeps a real reference and
  # static analysers don't flag MediaCentarr.Profile as unused.
  def metadata_for(scale), do: Profile.metadata(scale)
end
