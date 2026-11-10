defmodule MediaCentaur.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Boundary,
    top_level?: true,
    deps: [
      MediaCentaur.Capabilities,
      MediaCentaur.Features,
      MediaCentaur.NewReleases,
      MediaCentaur.Players,
      MediaCentaur.Social,
      MediaCentaur.Activities,
      MediaCentaur.RelaySync,
      MediaCentaur.Settings.Controls,
      MediaCentaur.Library,
      MediaCentaur.BootHeal,
      MediaCentaur.Maintenance,
      MediaCentaur.Pipeline,
      MediaCentaur.Review,
      MediaCentaur.Watcher,
      MediaCentaur.Settings,
      MediaCentaur.ReleaseTracking,
      MediaCentaur.Playback,
      MediaCentaur.Console,
      MediaCentaur.ErrorReports,
      MediaCentaur.Jobs,
      MediaCentaur.Acquisition,
      MediaCentaur.Downloads,
      MediaCentaur.WatchHistory,
      MediaCentaur.SelfUpdate,
      MediaCentaur.Settings.Preferences,
      MediaCentaur.TMDB,
      MediaCentaurWeb
    ]

  use Application

  alias MediaCentaur.Settings.Config

  @impl true
  def start(_type, _args) do
    Config.load!()

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

    # Every failed Oban job reaches the Console (ADR-077, rule 7).
    :ok = MediaCentaur.Jobs.attach()

    # The tree is the one statement of what runs (campaign
    # `supervision-tree.md`): a setting decides whether a child is started
    # — the FlagSupervisors under Watcher, Pipeline and Features.Runtime —
    # and the bootstrap runs in tree order, before Oban and every subsystem.
    children =
      [
        MediaCentaurWeb.Telemetry,
        MediaCentaur.Repo,
        {Phoenix.PubSub, name: MediaCentaur.PubSub},
        {Task.Supervisor, name: MediaCentaur.TaskSupervisor},
        # Before the bootstrap, so its lines reach the rings.
        MediaCentaur.Console.Supervisor,
        # Config overlay and orphan rescue, before Oban reads either.
        MediaCentaur.Application.Bootstrap,
        {Oban, oban_config()},
        MediaCentaur.ErrorReports.Supervisor
      ] ++
        settings_children(MediaCentaur.Cache.workers_run?()) ++
        [
          # The watchers start here, synchronously, when their flag is on:
          # Library.MediaFileAvailability reads their statuses at its init,
          # and the pipeline's startup recovery below relies on the order.
          MediaCentaur.Watcher.Supervisor,
          MediaCentaur.Library.Supervisor,
          MediaCentaur.ReleaseTracking.Supervisor,
          MediaCentaur.WatchHistory.Supervisor,
          MediaCentaur.Status.Supervisor
        ] ++
        http_client_children(Application.get_env(:media_centaur, :environment)) ++
        [
          MediaCentaur.TMDB.Supervisor,
          # Each feature's processes, started while its flag is on and
          # stopped when it goes off (ADR-081).
          {MediaCentaur.Features.Runtime, runtimes: feature_runtimes()},
          MediaCentaur.Pipeline.Supervisor,
          MediaCentaur.Pipeline.Image.Supervisor
        ] ++
        boot_heal_children(background_services?()) ++
        [
          MediaCentaur.SelfUpdate.Supervisor,
          MediaCentaur.Review.Supervisor,
          MediaCentaur.Acquisition.Supervisor
        ] ++
        single_process_listeners(background_services?()) ++
        [
          MediaCentaur.Playback.Supervisor,
          MediaCentaurWeb.Supervisor
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [
      strategy: :one_for_one,
      name: MediaCentaur.Supervisor,
      max_restarts: 10,
      max_seconds: 30
    ]

    Supervisor.start_link(children, opts)
  end

  # The acquisition queue starts paused when auto-grab is off
  # (`Settings.Services.start?/1`, read after the Bootstrap child has applied
  # the config); `Acquisition.AutoGrabService` pauses and resumes it live.
  # With `queues: false` (no background services) there is nothing to pause.
  defp oban_config do
    config = Application.fetch_env!(:media_centaur, Oban)

    with queues when is_list(queues) <- Keyword.get(config, :queues),
         true <- Keyword.has_key?(queues, :acquisition) do
      paused? = not MediaCentaur.Settings.Services.start?(:start_acquisition)
      Keyword.put(config, :queues, Keyword.update!(queues, :acquisition, &paused_queue(&1, paused?)))
    else
      _no_acquisition_queue -> config
    end
  end

  defp paused_queue(limit, paused?) when is_integer(limit), do: [limit: limit, paused: paused?]
  defp paused_queue(opts, paused?) when is_list(opts), do: Keyword.put(opts, :paused, paused?)

  # Network-free, idempotent backfills — background work, so only in an
  # instance that runs background services (see BootHeal). Placed after the
  # pipelines: the heals re-emit files for import.
  defp boot_heal_children(true), do: [MediaCentaur.BootHeal]
  defp boot_heal_children(false), do: []

  # The response cache is not started under :test: the suite's Req.Test
  # stubs would otherwise share entries across tests. Cache tests start
  # their own coordinator under a unique name.
  defp http_client_children(:test), do: []

  # `:showcase_mode` is bootstrap state read from the override TOML, so it
  # is already known here. It has two consequences, and a real install
  # gets neither: the demo supervises the generators that rebuild its
  # in-memory fabricated state, and its request store keeps no snapshot —
  # that history is fabricated fresh every boot by
  # `Showcase.SyntheticTraffic`, and restoring a snapshot would stack the
  # last boot's month under this one's. Real installs snapshot beside the
  # database (ADR-070).
  defp http_client_children(_env) do
    showcase? = MediaCentaur.Settings.Config.get(:showcase_mode)

    snapshot_dir =
      with false <- showcase?,
           path when is_binary(path) <- MediaCentaur.Settings.Config.get(:database_path) do
        Path.dirname(path)
      else
        _no_snapshot -> nil
      end

    [{MediaCentaur.HttpClient.Supervisor, snapshot_dir: snapshot_dir}] ++
      if showcase?, do: [MediaCentaur.Showcase.Supervisor], else: []
  end

  # Each feature's runtime (ADR-081): the children `Features.Runtime` runs
  # while the flag is on. Social dials relays, syncs with them and publishes
  # the person's acts; remote players holds the one open pairing code;
  # Discovery's scheduler enqueues one New Releases refresh when its
  # runtime starts, at boot or at turn-on, and one a day after that — the
  # shelf has no cron entry, so nothing of it runs while the feature is
  # off. The children that are background work keep the instance rule:
  # none in an instance without background services (the connection owner
  # applies the same rule to itself).
  defp feature_runtimes do
    %{
      social:
        [MediaCentaur.Social.Connections] ++
          background_only([MediaCentaur.RelaySync, MediaCentaur.Activities.Publisher]),
      players: [MediaCentaur.Players.Pairing],
      discovery: background_only([MediaCentaur.NewReleases.Scheduler])
    }
  end

  defp background_only(children), do: if(background_services?(), do: children, else: [])

  defp durable_diagnostics?, do: Application.get_env(:media_centaur, :durable_diagnostics, false)

  # The `:persistent_term` caches every derived cache reads first, and the
  # integration health state. Settings starts before Capabilities and
  # Controls so they prime from a warm upstream. Not under `:test`
  # (`Cache.workers_run?/0`): each runs its initial read in its own process,
  # which has no claim on a test's sandbox connection; the cached read paths
  # fall through to a live query when the key is unset.
  defp settings_children(false), do: []

  defp settings_children(true) do
    [
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Settings},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Capabilities},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Settings.Controls},
      # Per-integration health (configured? × test_state) in ETS, seeded
      # from the persisted tests; the same rule as the caches above — its
      # tests start their own instance.
      MediaCentaur.IntegrationHealth
    ]
  end

  # Subsystems whose only process is a listener: a supervisor of one would
  # add nothing. Background work, so none in an instance without
  # background services (under :test the sandbox-owned process could not
  # see their writes either).
  defp single_process_listeners(false), do: []

  defp single_process_listeners(true) do
    [MediaCentaur.EpisodeMapping.FileEventHandler, MediaCentaur.Downloads.QueueMonitor]
  end

  # Bootstrap state (`Settings.Config`): whether this instance does
  # anything on its own. False in the test env and in a measurement
  # server; every child that would act unprompted asks it.
  defp background_services?, do: Config.get(:background_services)

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MediaCentaurWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
