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
        # PubSub must start before Console.Buffer — Buffer's handle_cast
        # broadcasts to PubSub on every log entry append, including during
        # init when Ecto query logs land in its mailbox.
        {Phoenix.PubSub, name: MediaCentaur.PubSub},
        MediaCentaur.Console.Buffer,
        {MediaCentaur.Console.JournalSource,
         Application.get_env(:media_centaur, MediaCentaur.Console.JournalSource, [])},
        # Config overlay and orphan rescue, before Oban reads either.
        MediaCentaur.Application.Bootstrap,
        {Oban, oban_config()},
        # Before the cache workers: the ShellBadges cache prime reads
        # `ErrorReports.list_buckets/0` synchronously during its init.
        MediaCentaur.ErrorReports.Buckets
      ] ++
        cache_children(Application.get_env(:media_centaur, :environment)) ++
        [
          {Task.Supervisor, name: MediaCentaur.TaskSupervisor}
        ] ++
        http_client_children(Application.get_env(:media_centaur, :environment)) ++
        [
          MediaCentaur.TMDB.RateLimiter,
          MediaCentaur.TMDB.MetadataStats,
          # The watchers start here, synchronously, when their flag is on;
          # the pipeline's startup recovery below relies on that order.
          MediaCentaur.Watcher.Supervisor,
          # Each feature's processes, started while its flag is on and
          # stopped when it goes off (ADR-081).
          {MediaCentaur.Features.Runtime, runtimes: feature_runtimes()}
        ] ++
        [
          MediaCentaur.Library.BroadcastCoalescer,
          MediaCentaur.Library.MediaFileAvailability,
          MediaCentaur.Pipeline.Supervisor,
          MediaCentaur.Pipeline.Image.Supervisor
        ] ++
        boot_heal_children(background_services?()) ++
        [
          MediaCentaur.Library.AbsenceSweeper,
          MediaCentaur.Library.FileEventHandler,
          MediaCentaur.SelfUpdate.Updater,
          MediaCentaur.SelfUpdate.AutoApply,
          MediaCentaurWeb.DownloadsLive.SearchSession
        ] ++
        pubsub_listeners(background_services?()) ++
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

  # `:persistent_term`-backed cache workers. Not started in test mode:
  # each worker runs its initial DB read in its own process, which has no
  # claim on the test's sandbox connection. The cached read paths in
  # Capabilities, Controls, and SpoilerFree all fall through to a live
  # query when `:persistent_term` is unset, so tests get fresh-DB
  # semantics without the cache layer.
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

  defp cache_children(:test), do: []

  defp cache_children(_env) do
    [
      # Settings starts first so derived caches see a warm upstream.
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Settings},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Capabilities},
      {MediaCentaur.Cache.Worker, context: MediaCentaur.Settings.Controls},
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
  # Gated like the relay-connection owner it rides on: background work.
  # Under :test (no background services) the sync would otherwise
  # subscribe every FakeRelay a test stands up; relay_sync_test starts
  # its own by hand.
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

  defp diagnostics_children(true), do: [{MediaCentaur.ErrorReports.ShutdownMonitor, []}]
  defp diagnostics_children(false), do: []

  defp durable_diagnostics?, do: Application.get_env(:media_centaur, :durable_diagnostics, false)

  # The listeners react to library, release, playback and integration
  # events on their own — background work. An instance without
  # background services starts none (under :test the sandbox-owned
  # process could not see their writes either).
  defp pubsub_listeners(false), do: []

  defp pubsub_listeners(true) do
    [
      MediaCentaur.Library.Inbound,
      MediaCentaur.Review.Intake,
      MediaCentaur.Review.FileEventHandler,
      MediaCentaur.EpisodeMapping.FileEventHandler,
      MediaCentaur.ReleaseTracking.LibraryListener,
      MediaCentaur.ReleaseTracking.TmdbListener,
      MediaCentaur.Pipeline.TmdbProjection,
      MediaCentaur.WatchHistory.Recorder,
      MediaCentaur.Acquisition.Reactor,
      MediaCentaur.Downloads.QueueMonitor,
      MediaCentaur.Acquisition.Pursuits.InboundListener,
      MediaCentaur.Acquisition.Pursuits.QueueListener
    ]
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
