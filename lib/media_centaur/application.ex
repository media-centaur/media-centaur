defmodule MediaCentaur.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    MediaCentaur.Config.load!()

    :logger.add_primary_filter(
      :component_filter,
      {fn event, extra ->
         try do
           MediaCentaur.Log.filter(event, extra)
         catch
           :error, :undef -> :ignore
         end
       end, []}
    )

    children = [
      MediaCentaurWeb.Telemetry,
      MediaCentaur.Repo,
      %{
        id: :init_logging,
        start: {__MODULE__, :init_logging, []},
        restart: :temporary
      },
      {Phoenix.PubSub, name: MediaCentaur.PubSub},
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
      MediaCentaur.Library.FileTracker,
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

  @doc false
  def init_logging do
    MediaCentaur.Log.init()
    MediaCentaur.Log.init_framework_levels()
    :ignore
  end

  defp init_services do
    env = Application.get_env(:media_centaur, :environment, :dev)

    if should_start?(env, :start_watchers) do
      MediaCentaur.Watcher.Supervisor.start_watchers()
    end

    unless should_start?(env, :start_pipeline) do
      MediaCentaur.Pipeline.Supervisor.stop_pipeline()
      MediaCentaur.ImagePipeline.Supervisor.stop_pipeline()
    end
  end

  defp should_start?(env, service) do
    config_default = Application.get_env(:media_centaur, service, true)
    key = "services:#{env}:#{service}"

    case MediaCentaur.Library.get_setting_by_key(key) do
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
