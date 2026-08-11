defmodule MediaCentaur.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Boundary,
    top_level?: true,
    deps: [
      MediaCentaur.Capabilities,
      MediaCentaur.Controls,
      MediaCentaur.Library,
      MediaCentaur.Maintenance,
      MediaCentaur.Pipeline,
      MediaCentaur.Review,
      MediaCentaur.Watcher,
      MediaCentaur.Settings,
      MediaCentaur.ReleaseTracking,
      MediaCentaur.Playback,
      MediaCentaur.Console,
      MediaCentaur.ErrorReports,
      MediaCentaur.Acquisition,
      MediaCentaur.Downloads,
      MediaCentaur.WatchHistory,
      MediaCentaur.SelfUpdate,
      MediaCentaur.SpoilerFree,
      MediaCentaur.TMDB,
      MediaCentaurWeb
    ]

  use Application

  @impl true
  def start(_type, _args) do
    MediaCentaur.Config.load!()

    :logger.add_handler(
      :media_centaur_console,
      MediaCentaur.Console.Handler,
      %{level: :all, config: %{}}
    )

    # Durable diagnostics capture — an INDEPENDENT peer of the Console handler,
    # not downstream of it. Both receive logger events directly, so a crash or
    # backpressure in the volatile Console buffer cannot starve the durable
    # incident store. `level: :warning` lets :logger pre-filter to the tier we
    # persist (warning and above) before the handler is even invoked.
    #
    # Gated on the `:durable_diagnostics` flag (set in runtime.exs): on for the
    # production release, and for a dev instance acting as the always-on daily
    # driver (via MEDIA_CENTAUR_DURABLE_DIAGNOSTICS=1). Off under :test — a
    # globally-attached handler would funnel the whole suite's ambient
    # warning/error logs into the shared-sandbox DB via the global Buckets,
    # racing per-test teardown. Off for an ad-hoc `mix phx.server` too, so
    # throwaway dev iteration's hot-reload/mid-migration crashes don't mint
    # `:log` incidents onto the real Status page.
    if durable_diagnostics?() do
      :logger.add_handler(
        :media_centaur_diagnostics,
        MediaCentaur.ErrorReports.LogHandler,
        %{level: :warning, config: %{}}
      )
    end

    children =
      [
        MediaCentaurWeb.Telemetry,
        MediaCentaur.Repo,
        {Oban, Application.fetch_env!(:media_centaur, Oban)},
        # PubSub must start before Console.Buffer — Buffer's handle_cast
        # broadcasts to PubSub on every log entry append, including during
        # init when Ecto query logs land in its mailbox.
        {Phoenix.PubSub, name: MediaCentaur.PubSub},
        MediaCentaur.Console.Buffer,
        MediaCentaur.Console.JournalSource,
        # Before the cache workers: the ShellBadges cache prime reads
        # `ErrorReports.list_buckets/0` synchronously during its init.
        MediaCentaur.ErrorReports.Buckets
      ] ++
        cache_children(Application.get_env(:media_centaur, :environment)) ++
        [
          {Task.Supervisor, name: MediaCentaur.TaskSupervisor},
          MediaCentaur.TMDB.RateLimiter,
          MediaCentaur.TMDB.MetadataStats,
          MediaCentaur.Watcher.Supervisor,
          MediaCentaur.Library.BroadcastCoalescer,
          MediaCentaur.Library.Availability,
          MediaCentaur.Pipeline.Supervisor,
          MediaCentaur.Pipeline.Image.Supervisor,
          %{
            id: :init_services,
            start: {Task, :start_link, [fn -> init_services() end]},
            restart: :temporary
          },
          MediaCentaur.Library.AbsenceSweeper,
          MediaCentaur.Library.FileEventHandler,
          MediaCentaur.SelfUpdate.Updater,
          MediaCentaur.SelfUpdate.AutoApply,
          MediaCentaurWeb.IncomingLive.SearchSession
        ] ++
        pubsub_listeners(Application.get_env(:media_centaur, :environment)) ++
        diagnostics_children(durable_diagnostics?()) ++
        [
          MediaCentaur.Playback.Supervisor,
          MediaCentaurWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [
      strategy: :one_for_one,
      name: MediaCentaur.Supervisor,
      max_restarts: 10,
      max_seconds: 30
    ]

    children
    |> Supervisor.start_link(opts)
    |> post_supervisor_hooks()
  end

  @doc """
  Runs post-start hooks when the supervision tree came up successfully,
  or passes the error through unchanged when it didn't.

  Skipping the hooks on a failed start prevents misleading secondary
  errors — e.g. `Config.load_runtime_overrides/0` tries to read Settings
  from Repo, and if a child failed to start, Repo is already being torn
  down. The Repo-lookup crash that results hides the original cause of
  the failure. Guarding here keeps the first crash the only crash.
  """
  @spec post_supervisor_hooks({:ok, pid()} | {:error, term()}) ::
          {:ok, pid()} | {:error, term()}
  def post_supervisor_hooks({:ok, _pid} = result) do
    MediaCentaur.Config.load_runtime_overrides()

    # Hydrate the update-check cache from persisted state and, if the
    # last check is stale, enqueue a fresh one. Skipped in test mode so
    # the suite doesn't reach out to GitHub or fire inline Oban jobs.
    if MediaCentaur.SelfUpdate.enabled?() do
      MediaCentaur.SelfUpdate.boot!()
    end

    result
  end

  def post_supervisor_hooks({:error, _reason} = error), do: error

  defp init_services do
    toml_entries = Application.get_env(:media_centaur, :__raw_toml_media_dirs, [])

    try do
      :ok = MediaCentaur.Config.migrate_media_dirs_from_toml(toml_entries)
      :ok = MediaCentaur.Config.refresh_media_dirs_from_settings()
      :ok = MediaCentaur.Config.load_runtime_overrides()

      count = length(MediaCentaur.Config.media_dirs_entries())
      require MediaCentaur.Log
      MediaCentaur.Log.info(:library, "media_dirs: #{count} entries active")
    rescue
      error ->
        require MediaCentaur.Log

        MediaCentaur.Log.error(
          :library,
          "config migration failed: #{Exception.format(:error, error, __STACKTRACE__)}"
        )
    end

    env = Application.get_env(:media_centaur, :environment, :dev)

    # Heal extra display names against the current parser rules — a parser fix
    # shipped in an update reaches existing records on the next boot, no operator
    # action. Network-free, idempotent, skipped under :test (see Maintenance).
    MediaCentaur.Maintenance.heal_extra_names_on_boot(env)

    # Backfill ExtraFile rows for extras imported before the ingest path wrote
    # them, so they become "linked" and stop re-running through the pipeline on
    # every rescan. Network-free, idempotent, skipped under :test.
    MediaCentaur.Maintenance.backfill_extra_files_on_boot(env)

    # Probe technical metadata (container title, duration, codecs) for files
    # imported before the media-info feature. Local ffprobe only, idempotent,
    # skipped under :test.
    MediaCentaur.Maintenance.probe_media_info_on_boot(env)

    # Move legacy images/tracking/ artwork into TmdbArtwork's typed
    # layout. Filesystem-only, idempotent, self-retiring, skipped under
    # :test. Pairs with the release_tracking_items path-column data
    # migration.
    MediaCentaur.ReleaseTracking.migrate_artwork_layout_on_boot(env)

    if should_start?(env, :start_watchers) do
      MediaCentaur.Watcher.Supervisor.start_watchers()
      MediaCentaur.Watcher.Supervisor.start_image_dir_monitors()
    end

    if !should_start?(env, :start_pipeline) do
      MediaCentaur.Pipeline.Supervisor.stop_pipeline()
      MediaCentaur.Pipeline.Image.Supervisor.stop_pipeline()
    end

    if !should_start?(env, :start_acquisition) do
      MediaCentaur.Acquisition.pause_auto_grab()
    end
  end

  # `:persistent_term`-backed cache workers. Not started in test mode:
  # each worker runs its initial DB read in its own process, which has no
  # claim on the test's sandbox connection. The cached read paths in
  # Capabilities, Controls, and SpoilerFree all fall through to a live
  # query when `:persistent_term` is unset, so tests get fresh-DB
  # semantics without the cache layer.
  defp cache_children(:test), do: []

  defp cache_children(_env) do
    [
      # Settings starts first so derived caches see a warm upstream.
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Settings},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Capabilities},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Controls},
      # ETS-backed Library projections (ADR-041).
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Library.Views.Browse},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Library.Views.ContinueWatching},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Library.Views.Detail},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Library.Views.HeroCandidates},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Library.Views.RecentlyAdded},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Library.Views.Search},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.ReleaseTracking.Views.ComingUp},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.WatchHistory.Views.Summary},
      # Status-page projections (instant-navigation campaign). Async prime:
      # both run disk probes (`df`, per-image checks) that must never block
      # boot; the interval is the drift net for slices with no source event.
      {MediaCentaur.Cache.Worker,
       context: MediaCentaur.Status.Views.Overview,
       prime: :async,
       refresh_interval_ms: to_timeout(minute: 10)},
      {MediaCentaur.Cache.Worker,
       context: MediaCentaur.Status.Views.Storage,
       prime: :async,
       refresh_interval_ms: to_timeout(minute: 5)},
      # Sidebar badge counts (diagnostics / review / mapping) — read by the
      # ShellBadges on_mount hook on every navigation, so they must never
      # cost a query on the mount path.
      {MediaCentaur.Cache.Worker, context: MediaCentaurWeb.ShellBadges},
      # Pillar-2 GenServer (ADR-041) — owns active watch-progress
      # state in ETS, debounce-flushes to library_watch_progress.
      MediaCentaur.Library.Progress.Worker,
      # Per-integration health (configured? × test_state) — drives the
      # Setup Tour gate and (future) pipeline auto-retry on TMDB recovery.
      MediaCentaur.IntegrationHealth
    ]
  end

  # PubSub listener GenServers — thin wrappers that route messages to public
  # API functions. Not started in test mode because tests call the public
  # functions directly and PubSub broadcasts would cause sandbox errors.
  # Unclean-shutdown detection. Gated on `:durable_diagnostics` (same flag as the
  # incident LogHandler). Off under :test — at app boot there is no sandbox owner,
  # so its raise-fault-on-unclean would fail; the marker logic is tested directly
  # via ShutdownMarker / a :path-injected ShutdownMonitor. Off for an ad-hoc
  # `mix phx.server` too — when a separate prod release is also running they would
  # fight over the SAME marker file, minting false "did not shut down cleanly"
  # warnings. The opted-in daily driver (prod release, or dev with the env var)
  # is the sole instance, so it owns the marker.
  defp diagnostics_children(true), do: [{MediaCentaur.ErrorReports.ShutdownMonitor, []}]
  defp diagnostics_children(false), do: []

  defp durable_diagnostics?, do: Application.get_env(:media_centaur, :durable_diagnostics, false)

  defp pubsub_listeners(:test), do: []

  defp pubsub_listeners(_env) do
    [
      MediaCentaur.Library.Inbound,
      MediaCentaur.Review.Intake,
      MediaCentaur.ReleaseTracking.Refresher,
      MediaCentaur.WatchHistory.Recorder,
      MediaCentaur.Acquisition.Reactor,
      MediaCentaur.Downloads.QueueMonitor,
      MediaCentaur.Acquisition.Pursuits.InboundListener
    ]
  end

  defp should_start?(env, service) do
    config_default = Application.get_env(:media_centaur, service, true)
    key = "services:#{env}:#{service}"

    case MediaCentaur.Settings.get_by_key(key) do
      %{value: %{"enabled" => true}} -> true
      %{value: %{"enabled" => false}} -> false
      _ -> config_default
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MediaCentaurWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
