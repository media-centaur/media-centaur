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

    start_watchers? = Application.get_env(:media_centaur, :start_watchers, true)
    start_pipeline? = Application.get_env(:media_centaur, :start_pipeline, true)

    children =
      Enum.reject(
        [
          MediaCentaurWeb.Telemetry,
          MediaCentaur.Repo,
          %{
            id: :init_logging,
            start: {__MODULE__, :init_logging, []},
            restart: :temporary
          },
          {DNSCluster, query: Application.get_env(:media_centaur, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: MediaCentaur.PubSub},
          {Task.Supervisor, name: MediaCentaur.TaskSupervisor},
          MediaCentaur.TMDB.RateLimiter,
          if(start_watchers?, do: MediaCentaur.Watcher.Supervisor),
          if(start_watchers?,
            do: %{
              id: :start_watchers,
              start: {Task, :start_link, [&MediaCentaur.Watcher.Supervisor.start_watchers/0]},
              restart: :temporary
            }
          ),
          MediaCentaur.Pipeline.Stats,
          if(start_pipeline?, do: MediaCentaur.Pipeline),
          MediaCentaur.ImagePipeline.Stats,
          if(start_pipeline?, do: MediaCentaur.ImagePipeline),
          MediaCentaur.Library.FileTracker,
          MediaCentaur.Playback.Supervisor,
          MediaCentaurWeb.Endpoint
        ],
        &is_nil/1
      )

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MediaCentaur.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  def init_logging do
    MediaCentaur.Log.init()
    MediaCentaur.Log.init_framework_levels()
    :ignore
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MediaCentaurWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
