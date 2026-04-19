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
        {Task.Supervisor, name: MediaCentarr.TaskSupervisor},
        MediaCentarr.TMDB.RateLimiter,
        MediaCentarr.Watcher.Supervisor,
        MediaCentarr.Pipeline.Supervisor,
        MediaCentarr.Pipeline.Image.Supervisor,
        %{
          id: :init_services,
          start: {Task, :start_link, [fn -> init_services() end]},
          restart: :temporary
        },
        MediaCentarr.Watcher.FilePresence,
        MediaCentarr.Library.FileEventHandler,
        MediaCentarr.SelfUpdate.Updater
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

    result = Supervisor.start_link(children, opts)
    MediaCentarr.Config.load_runtime_overrides()

    # Hydrate the update-check cache from persisted state and, if the
    # last check is stale, enqueue a fresh one. Skipped in test mode so
    # the suite doesn't reach out to GitHub or fire inline Oban jobs.
    if Application.get_env(:media_centarr, :environment, :dev) != :test do
      MediaCentarr.SelfUpdate.boot!()
    end

    result
  end

  defp init_services do
    toml_entries = Application.get_env(:media_centarr, :__raw_toml_watch_dirs, [])
    :ok = MediaCentarr.Config.migrate_watch_dirs_from_toml(toml_entries)
    :ok = MediaCentarr.Config.refresh_watch_dirs_from_settings()

    env = Application.get_env(:media_centarr, :environment, :dev)

    if should_start?(env, :start_watchers) do
      MediaCentarr.Watcher.Supervisor.start_watchers()
      MediaCentarr.Watcher.Supervisor.start_image_dir_monitors()
    end

    if !should_start?(env, :start_pipeline) do
      MediaCentarr.Pipeline.Supervisor.stop_pipeline()
      MediaCentarr.Pipeline.Image.Supervisor.stop_pipeline()
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
      MediaCentarr.Acquisition
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
