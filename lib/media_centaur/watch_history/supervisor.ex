defmodule MediaCentaur.WatchHistory.Supervisor do
  @moduledoc """
  WatchHistory's processes: the `Views.Summary` projection worker (not
  under `:test`, `MediaCentaur.Cache.workers_run?/0`) and, in instances that
  run background services, the `Recorder` of playback completions.
  Independent, `:one_for_one`.
  """
  use Supervisor

  alias MediaCentaur.Cache
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.WatchHistory

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    workers? = Cache.workers_run?()
    background? = Config.get(:background_services)

    children =
      if(workers?, do: [{Cache.Worker, context: WatchHistory.Views.Summary}], else: []) ++
        if(background?, do: [WatchHistory.Recorder], else: [])

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end
end
