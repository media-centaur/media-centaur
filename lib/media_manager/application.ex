defmodule MediaManager.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    MediaManager.Config.load!()

    :logger.add_primary_filter(
      :component_filter,
      {fn event, extra ->
         try do
           MediaManager.Log.filter(event, extra)
         catch
           :error, :undef -> :ignore
         end
       end, []}
    )

    start_watchers? = Application.get_env(:media_manager, :start_watchers, true)
    start_pipeline? = Application.get_env(:media_manager, :start_pipeline, true)

    children =
      Enum.reject(
        [
          MediaManagerWeb.Telemetry,
          MediaManager.Repo,
          %{
            id: :init_logging,
            start: {__MODULE__, :init_logging, []},
            restart: :temporary
          },
          {DNSCluster, query: Application.get_env(:media_manager, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: MediaManager.PubSub},
          {Task.Supervisor, name: MediaManager.TaskSupervisor},
          MediaManager.TMDB.RateLimiter,
          if(start_watchers?, do: MediaManager.Watcher.Supervisor),
          if(start_watchers?,
            do: %{
              id: :start_watchers,
              start: {Task, :start_link, [&MediaManager.Watcher.Supervisor.start_watchers/0]},
              restart: :temporary
            }
          ),
          if(start_pipeline?, do: MediaManager.Pipeline),
          MediaManager.Playback.Supervisor,
          MediaManagerWeb.Endpoint
        ],
        &is_nil/1
      )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MediaManager.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  def init_logging do
    MediaManager.Log.init()
    MediaManager.Log.init_framework_levels()
    :ignore
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MediaManagerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
