defmodule MediaCentaur.ReleaseTracking.Supervisor do
  @moduledoc """
  ReleaseTracking's processes: the `Views.ComingUp` projection worker (not
  under `:test`, `MediaCentaur.Cache.workers_run?/0`) and, in instances that
  run background services, the `LibraryListener` and `TmdbListener`.
  Independent, `:one_for_one`.
  """
  use Supervisor

  alias MediaCentaur.Cache
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Settings.Config

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    workers? = Cache.workers_run?()
    background? = Config.get(:background_services)

    children =
      if(workers?, do: [{Cache.Worker, context: ReleaseTracking.Views.ComingUp}], else: []) ++
        if(background?, do: [ReleaseTracking.LibraryListener, ReleaseTracking.TmdbListener], else: [])

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end
end
