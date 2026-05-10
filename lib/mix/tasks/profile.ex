defmodule Mix.Tasks.Profile do
  @shortdoc "Run the projection profiling suite and write a markdown report"
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Orchestrates an end-to-end profile run (ADR-041): seed
  representative library data, run every `MediaCentarr.Profile.Suite`
  via Benchee, time every top-level LiveView mount via
  `Phoenix.LiveViewTest`, and write a markdown report under
  `priv/profiling/runs/`.

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

  ## Output

  Writes `priv/profiling/runs/<ISO8601>.md` and updates the
  `latest.md` symlink. Prints the report path on completion.
  """
  use Mix.Task

  alias MediaCentarr.Profile
  alias MediaCentarr.Profile.{Bench, Loader, Mounts, Reporter}

  @cache_ets :library_view_continue_watching
  @cache_warm_timeout_ms 5000

  @impl true
  def run(args) do
    require_config_override!()

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [scale: :string, skip_seed: :boolean]
      )

    scale = parse_scale(opts[:scale])
    skip_seed? = Keyword.get(opts, :skip_seed, false)

    Mix.Task.run("app.start")
    wait_for_cache_workers!()

    metadata = Profile.metadata(scale)

    if !skip_seed? do
      Mix.shell().info("Seeding (#{scale})…")

      seeded = Loader.amplify!(scale)

      Mix.shell().info("  Seeded #{length(seeded.movies)} movies, #{length(seeded.episodes)} episodes.")

      # The projection's Cache.Worker will refresh asynchronously when
      # it sees the entities_changed broadcast, but Loader writes via
      # public Library APIs that don't broadcast. Force a refresh so
      # the warm-cache scenarios see the seeded data.
      MediaCentarr.Library.Views.ContinueWatching.refresh_cache()
    end

    Mix.shell().info("Running benchmarks…")
    bench_results = Bench.run_all()

    Mix.shell().info("Timing page mounts…")
    mount_results = Mounts.run_all()

    Mix.shell().info("Writing report…")
    path = Reporter.write(metadata, bench_results, mount_results)

    Mix.shell().info("""

    Report: #{path}
    Latest: #{Reporter.runs_dir()}/latest.md
    """)
  end

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
