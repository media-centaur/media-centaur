if Mix.env() in [:dev, :test] do
  defmodule Mix.Tasks.Profile do
    @shortdoc "Run the projection profiling suite, write markdown + JSON, diff vs baseline"
    use Boundary, top_level?: true, check: [in: false, out: false]

    @moduledoc """
    Orchestrates an end-to-end profile run (ADR-041): seed
    representative library data, run every `MediaCentarr.Profile.Suite`
    via Benchee, time every top-level LiveView mount via
    `Phoenix.LiveViewTest`, and write both a markdown report and a
    canonical JSON snapshot under `priv/profiling/runs/`.

    When a baseline JSON exists for the current scale at
    `priv/profiling/baseline-<scale>.json`, the run is automatically
    diffed against it. Deltas land in the run's JSON `:deltas` field,
    the markdown's `## Deltas` section, and a focused terminal
    summary (regressions and improvements outside ±10%).

    Refuses to run without `MEDIA_CENTARR_CONFIG_OVERRIDE` set so a
    misconfigured invocation cannot mutate the user's dev or prod DB.
    `scripts/profile` sets this automatically — invoke that for the
    one-button experience.

    ## Options

        --scale=small   (default)   100 movies, 12 in-progress    ~30 s
        --scale=medium              1000 movies, 50 in-progress   ~2 min
        --scale=large               5000 movies, 100 in-progress  ~5 min

        --skip-seed                 Re-run measurement against the existing DB
                                    (faster iteration on report shape)

        --rebaseline                After printing the diff, prompt to
                                    promote this run to
                                    `priv/profiling/baseline-<scale>.{md,json}`.
                                    Returns `false` in non-interactive
                                    contexts so CI cannot rebaseline by
                                    accident.

        --yes                       When combined with `--rebaseline`,
                                    skip the confirmation prompt and
                                    promote unconditionally. Designed
                                    for agent / script-driven runs
                                    where there is no TTY to answer
                                    the prompt. The flag must be
                                    explicit — bare `--rebaseline`
                                    still requires interactive consent.

    ## Output

    Writes:

      * `priv/profiling/runs/<ISO8601>.md`   — human-readable report
      * `priv/profiling/runs/<ISO8601>.json` — canonical machine-readable
      * `priv/profiling/runs/latest.md`      — symlink to most recent
      * `priv/profiling/runs/latest.json`    — symlink to most recent

    Prints both report paths and the delta summary on completion.
    """
    use Mix.Task

    alias MediaCentarr.Profile
    alias MediaCentarr.Profile.{Bench, Diff, Loader, Mounts, Reporter, RunData}

    @cache_ets :library_view_continue_watching
    @cache_warm_timeout_ms 5000

    @impl true
    def run(args) do
      require_config_override!()

      {opts, _, _} =
        OptionParser.parse(args,
          strict: [scale: :string, skip_seed: :boolean, rebaseline: :boolean, yes: :boolean]
        )

      scale = parse_scale(opts[:scale])
      skip_seed? = Keyword.get(opts, :skip_seed, false)
      rebaseline? = Keyword.get(opts, :rebaseline, false)
      yes? = Keyword.get(opts, :yes, false)

      Mix.Task.run("app.start")
      wait_for_cache_workers!()

      metadata = Profile.metadata(scale)

      if !skip_seed? do
        Mix.shell().info("Seeding (#{scale})…")
        seeded = Loader.amplify!(scale)

        Mix.shell().info(
          "  Seeded #{length(seeded.movies)} movies, #{length(seeded.episodes)} episodes."
        )

        # Loader writes through public Library APIs that don't broadcast
        # entity changes, so the projection's Cache.Worker hasn't refreshed.
        # Force a refresh so the warm-cache scenarios see the seeded data.
        MediaCentarr.Library.Views.ContinueWatching.refresh_cache()
      end

      Mix.shell().info("Running benchmarks…")
      bench_results = Bench.run_all()

      Mix.shell().info("Timing page mounts…")
      mount_results = Mounts.run_all()

      run_data =
        metadata
        |> RunData.build(bench_results, mount_results)
        |> attach_deltas(scale)

      Mix.shell().info("Writing report…")
      %{markdown: md_path, json: json_path} = Reporter.write(run_data)

      print_terminal_summary(run_data, md_path, json_path)

      if rebaseline?, do: maybe_rebaseline(scale, md_path, json_path, yes?)
    end

    # ---- Rebaseline ----------------------------------------------------------

    defp maybe_rebaseline(scale, md_path, json_path, yes?) do
      proceed? =
        if yes? do
          Mix.shell().info("\n--yes passed — rebaselining without prompt.")
          true
        else
          Mix.shell().yes?("\nReplace baseline-#{scale}.{md,json} with this run?",
            default: :no
          )
        end

      if proceed? do
        md_dest = Path.join("priv/profiling", "baseline-#{scale}.md")
        json_dest = Path.join("priv/profiling", "baseline-#{scale}.json")

        File.mkdir_p!("priv/profiling")
        File.cp!(md_path, md_dest)
        File.cp!(json_path, json_dest)

        Mix.shell().info("""

        Baseline updated:
          #{md_dest}
          #{json_dest}

        Commit with:
          jj describe -m "perf: rebaseline profile (scale: #{scale})"
        """)
      else
        Mix.shell().info("Baseline unchanged.")
      end
    end

    # ---- Baseline + diff -----------------------------------------------------

    defp attach_deltas(%RunData{} = run, scale) do
      case Reporter.baseline_json_path(scale) do
        :none ->
          Mix.shell().info("(no baseline-#{scale}.json — skipping diff)")
          run

        {:ok, path} ->
          case Reporter.load_baseline(path) do
            {:ok, baseline} ->
              apply_diff(run, baseline)

            {:error, reason} ->
              Mix.shell().error("Failed to load baseline at #{path}: #{inspect(reason)}")
              run
          end
      end
    end

    defp apply_diff(%RunData{} = run, %RunData{} = baseline) do
      case Diff.against(run, baseline) do
        {:ok, deltas} ->
          RunData.with_deltas(run, deltas)

        {:error, reason} ->
          Mix.shell().error("Skipping diff: #{inspect(reason)}")
          run
      end
    end

    # ---- Terminal summary ----------------------------------------------------

    defp print_terminal_summary(%RunData{deltas: nil} = run, md_path, json_path) do
      Mix.shell().info("""

      Profile run #{run.metadata.run_id} (scale: #{run.metadata.scale}).
      No baseline to compare against.

      Report: #{md_path}
      JSON:   #{json_path}
      """)
    end

    defp print_terminal_summary(%RunData{deltas: deltas} = run, md_path, json_path) do
      against = deltas.compared_against
      summary = deltas.summary
      flagged = Enum.reject(deltas.metrics, &(&1.classification in [:stable, :new]))

      Mix.shell().info("""

      Profile run #{run.metadata.run_id} (scale: #{run.metadata.scale})
      vs baseline #{against.run_id} (sha #{against.git_sha}).
      """)

      if flagged == [] do
        Mix.shell().info(
          "  ✓ All #{summary.total} metrics within ±#{deltas.thresholds.stable}% of baseline."
        )
      else
        flagged
        |> Enum.sort_by(&sort_key/1)
        |> Enum.each(&print_flagged/1)

        stable = Map.get(summary, :stable, 0)

        Mix.shell().info(
          "\n  #{stable} of #{summary.total} metrics stable (within ±#{deltas.thresholds.stable}%)."
        )
      end

      Mix.shell().info("""

      Report: #{md_path}
      JSON:   #{json_path}
      """)
    end

    defp sort_key(metric) do
      severity =
        case metric.classification do
          :REGRESSION -> 0
          :regression -> 1
          :IMPROVEMENT -> 2
          :improvement -> 3
          _ -> 4
        end

      {severity, -abs(metric.delta_pct || 0.0)}
    end

    defp print_flagged(metric) do
      glyph = classification_glyph(metric.classification)
      label = metric_label(metric)

      arrow =
        "#{format_value(metric.metric, metric.baseline)} → #{format_value(metric.metric, metric.current)}"

      pct = format_delta_pct(metric.delta_pct)

      Mix.shell().info("  #{glyph} #{pad(label, 60)} #{pad(arrow, 28)} #{pct}")
    end

    defp classification_glyph(:REGRESSION), do: "⚠ REGRESSION "
    defp classification_glyph(:regression), do: "⚠ regression "
    defp classification_glyph(:IMPROVEMENT), do: "↓ IMPROVEMENT"
    defp classification_glyph(:improvement), do: "↓ improvement"
    defp classification_glyph(_), do: "  "

    defp metric_label(%{
           category: :microbenchmark,
           suite: suite,
           input: input,
           scenario: scenario,
           metric: m
         }) do
      "#{trim_suite(suite)} · #{input} · #{scenario} (#{m})"
    end

    defp metric_label(%{category: :page_mount, route: route, metric: m}) do
      "mount #{route} (#{m})"
    end

    defp metric_label(%{category: :ets_memory, table: table, metric: _m}) do
      "ETS :#{table} bytes"
    end

    defp trim_suite("Library.Views." <> rest), do: rest
    defp trim_suite(name), do: name

    defp format_value(metric_name, value) when is_number(value) do
      name = Atom.to_string(metric_name)

      cond do
        String.ends_with?(name, "_ns") -> format_time_ns(value)
        String.ends_with?(name, "_us") -> format_time_us(value)
        metric_name == :bytes -> format_bytes(value)
        true -> "#{value}"
      end
    end

    defp format_value(_, nil), do: "—"

    defp format_time_ns(ns) when ns < 1000, do: "#{Float.round(ns * 1.0, 0)} ns"
    defp format_time_ns(ns) when ns < 1_000_000, do: "#{Float.round(ns / 1000, 2)} µs"
    defp format_time_ns(ns), do: "#{Float.round(ns / 1_000_000, 2)} ms"

    defp format_time_us(us) when us < 1000, do: "#{us} µs"
    defp format_time_us(us) when us < 1_000_000, do: "#{Float.round(us / 1000, 2)} ms"
    defp format_time_us(us), do: "#{Float.round(us / 1_000_000, 2)} s"

    defp format_bytes(bytes) when bytes < 1024, do: "#{trunc(bytes)} B"
    defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
    defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 2)} MB"

    defp format_delta_pct(pct) when is_number(pct) do
      sign = if pct >= 0, do: "+", else: ""
      "(#{sign}#{Float.round(pct, 1)}%)"
    end

    defp format_delta_pct(_), do: ""

    defp pad(text, width) do
      text = to_string(text)
      pad = max(0, width - String.length(text))
      text <> String.duplicate(" ", pad)
    end

    # ---- Boilerplate ---------------------------------------------------------

    defp parse_scale(nil), do: :small

    defp parse_scale(scale) do
      atom = String.to_existing_atom(scale)

      if Profile.valid_scale?(atom) do
        atom
      else
        Mix.raise(
          "Invalid --scale=#{scale}. Valid: #{Enum.map_join(Profile.scales(), ", ", &Atom.to_string/1)}"
        )
      end
    rescue
      ArgumentError ->
        Mix.raise(
          "Invalid --scale=#{scale}. Valid: #{Enum.map_join(Profile.scales(), ", ", &Atom.to_string/1)}"
        )
    end

    defp require_config_override! do
      case System.get_env("MEDIA_CENTARR_CONFIG_OVERRIDE") do
        override when is_binary(override) and override != "" ->
          :ok

        _ ->
          Mix.raise("""
          mix profile refuses to run without MEDIA_CENTARR_CONFIG_OVERRIDE.

          Use the script entry point (sets the override automatically):

              scripts/profile

          Or invoke directly with the shipped profile config:

              MEDIA_CENTARR_CONFIG_OVERRIDE=defaults/media-centarr-profile.toml mix profile

          This prevents profiling against the default dev/prod DB.
          """)
      end
    end

    defp wait_for_cache_workers! do
      deadline = System.monotonic_time(:millisecond) + @cache_warm_timeout_ms
      poll_for_table(deadline)
    end

    defp poll_for_table(deadline) do
      cond do
        :ets.whereis(@cache_ets) != :undefined ->
          :ok

        System.monotonic_time(:millisecond) >= deadline ->
          Mix.raise("""
          Timed out waiting for ContinueWatching projection ETS table.

          Likely the Cache.Worker did not start — check application
          config and Application.cache_children/1.
          """)

        true ->
          Process.sleep(50)
          poll_for_table(deadline)
      end
    end
  end
end
