defmodule MediaCentarr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  use Boundary,
    top_level?: true,
    deps: [
      MediaCentarr.Library,
      MediaCentarr.Pipeline,
      MediaCentarr.Review,
      MediaCentarr.Watcher,
      MediaCentarr.Settings,
      MediaCentarr.ReleaseTracking,
      MediaCentarr.Playback,
      MediaCentarr.Console,
      MediaCentarr.ErrorReports,
      MediaCentarr.Acquisition,
      MediaCentarr.WatchHistory,
      MediaCentarr.SelfUpdate,
      MediaCentarr.TMDB,
      MediaCentarrWeb
    ]

  use Application

  @impl true
  def start(_type, _args) do
    MediaCentarr.Config.load!()

    :logger.add_handler(
      :media_centarr_console,
      MediaCentarr.Console.Handler,
      %{level: :all, config: %{}}
    )

    children =
      [
        MediaCentarrWeb.Telemetry,
        MediaCentarr.Repo,
        {Oban, Application.fetch_env!(:media_centarr, Oban)},
        # PubSub must start before Console.Buffer — Buffer's handle_cast
        # broadcasts to PubSub on every log entry append, including during
        # init when Ecto query logs land in its mailbox.
        {Phoenix.PubSub, name: MediaCentarr.PubSub},
        MediaCentarr.Console.Buffer,
        MediaCentarr.Console.JournalSource,
        MediaCentarr.ErrorReports.Buckets,
        {Task.Supervisor, name: MediaCentarr.TaskSupervisor},
        MediaCentarr.TMDB.RateLimiter,
        MediaCentarr.Watcher.Supervisor,
        MediaCentarr.Library.BroadcastCoalescer,
        MediaCentarr.Library.Availability,
        MediaCentarr.Pipeline.Supervisor,
        MediaCentarr.Pipeline.Image.Supervisor,
        %{
          id: :init_services,
          start: {Task, :start_link, [fn -> init_services() end]},
          restart: :temporary
        },
        MediaCentarr.Watcher.FilePresence,
        MediaCentarr.Library.FileEventHandler,
        MediaCentarr.SelfUpdate.Updater,
        MediaCentarr.Acquisition.SearchSession
      ] ++
        pubsub_listeners(Application.get_env(:media_centarr, :environment)) ++
        [
          MediaCentarr.Playback.Supervisor,
          MediaCentarrWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [
      strategy: :one_for_one,
      name: MediaCentarr.Supervisor,
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
    MediaCentarr.Config.load_runtime_overrides()

    # Hydrate the update-check cache from persisted state and, if the
    # last check is stale, enqueue a fresh one. Skipped in test mode so
    # the suite doesn't reach out to GitHub or fire inline Oban jobs.
    if MediaCentarr.SelfUpdate.enabled?() do
      MediaCentarr.SelfUpdate.boot!()
    end

    result
  end

  def post_supervisor_hooks({:error, _reason} = error), do: error

  defp init_services do
    toml_entries = Application.get_env(:media_centarr, :__raw_toml_watch_dirs, [])
    toml_runtime = Application.get_env(:media_centarr, :__raw_toml_runtime_keys, %{})

    try do
      :ok = MediaCentarr.Config.migrate_watch_dirs_from_toml(toml_entries)
      :ok = MediaCentarr.Config.migrate_runtime_keys_from_toml(toml_runtime)
      :ok = MediaCentarr.Config.refresh_watch_dirs_from_settings()
      :ok = MediaCentarr.Config.load_runtime_overrides()

      count = length(MediaCentarr.Config.watch_dirs_entries())
      require MediaCentarr.Log
      MediaCentarr.Log.info(:library, "watch_dirs: #{count} entries active")
    rescue
      error ->
        require MediaCentarr.Log

        MediaCentarr.Log.error(
          :library,
          "config migration failed: #{Exception.format(:error, error, __STACKTRACE__)}"
        )
    end

    env = Application.get_env(:media_centarr, :environment, :dev)

    if should_start?(env, :start_watchers) do
      MediaCentarr.Watcher.Supervisor.start_watchers()
      MediaCentarr.Watcher.Supervisor.start_image_dir_monitors()
    end

    if !should_start?(env, :start_pipeline) do
      MediaCentarr.Pipeline.Supervisor.stop_pipeline()
      MediaCentarr.Pipeline.Image.Supervisor.stop_pipeline()
    end

    if !should_start?(env, :start_acquisition) do
      MediaCentarr.Acquisition.pause_auto_grab()
    end
  end

  # PubSub listener GenServers — thin wrappers that route messages to public
  # API functions. Not started in test mode because tests call the public
  # functions directly and PubSub broadcasts would cause sandbox errors.
  defp pubsub_listeners(:test), do: []

  defp pubsub_listeners(_env) do
    [
      MediaCentarr.Library.Inbound,
      MediaCentarr.Review.Intake,
      MediaCentarr.ReleaseTracking.Refresher,
      MediaCentarr.WatchHistory.Recorder,
      MediaCentarr.Acquisition,
      MediaCentarr.Acquisition.QueueMonitor
    ]
  end

  defp should_start?(env, service) do
    config_default = Application.get_env(:media_centarr, service, true)
    key = "services:#{env}:#{service}"

    case MediaCentarr.Settings.get_by_key(key) do
      {:ok, %{value: %{"enabled" => true}}} -> true
      {:ok, %{value: %{"enabled" => false}}} -> false
      _ -> config_default
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MediaCentarrWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
