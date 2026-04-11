defmodule MediaCentaur.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    MediaCentaur.Config.load!()

    :logger.add_handler(
      :media_centaur_console,
      MediaCentaur.Console.Handler,
      %{level: :all, config: %{}}
    )

    children =
      [
        MediaCentaurWeb.Telemetry,
        MediaCentaur.Repo,
        # PubSub must start before Console.Buffer — Buffer's handle_cast
        # broadcasts to PubSub on every log entry append, including during
        # init when Ecto query logs land in its mailbox.
        {Phoenix.PubSub, name: MediaCentaur.PubSub},
        MediaCentaur.Console.Buffer,
        {Task.Supervisor, name: MediaCentaur.TaskSupervisor},
        MediaCentaur.TMDB.RateLimiter,
        MediaCentaur.Watcher.Supervisor,
        MediaCentaur.Pipeline.Supervisor,
        MediaCentaur.ImagePipeline.Supervisor,
        %{
          id: :init_services,
          start: {Task, :start_link, [fn -> init_services() end]},
          restart: :temporary
        },
        MediaCentaur.Watcher.FilePresence,
        MediaCentaur.Library.FileEventHandler
      ] ++
        pubsub_listeners(Application.get_env(:media_centaur, :environment)) ++
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

  defp init_services do
    env = Application.get_env(:media_centaur, :environment, :dev)

    if should_start?(env, :start_watchers) do
      MediaCentaur.Watcher.Supervisor.start_watchers()
      MediaCentaur.Watcher.Supervisor.start_image_dir_monitors()
    end

    unless should_start?(env, :start_pipeline) do
      MediaCentaur.Pipeline.Supervisor.stop_pipeline()
      MediaCentaur.ImagePipeline.Supervisor.stop_pipeline()
    end
  end

  # PubSub listener GenServers — thin wrappers that route messages to public
  # API functions. Not started in test mode because tests call the public
  # functions directly and PubSub broadcasts would cause sandbox errors.
  defp pubsub_listeners(:test), do: []

  defp pubsub_listeners(_env) do
    [
      MediaCentaur.Library.Inbound,
      MediaCentaur.Review.Intake,
      MediaCentaur.ReleaseTracking.Refresher,
      MediaCentaur.WatchHistory.Recorder
    ]
  end

  defp should_start?(env, service) do
    config_default = Application.get_env(:media_centaur, service, true)
    key = "services:#{env}:#{service}"

    case MediaCentaur.Settings.get_by_key(key) do
      {:ok, %{value: %{"enabled" => true}}} -> true
      {:ok, %{value: %{"enabled" => false}}} -> false
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
