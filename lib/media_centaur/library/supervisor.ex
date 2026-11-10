defmodule MediaCentaur.Library.Supervisor do
  @moduledoc """
  The Library context's processes under one supervisor with one restart
  budget (`:one_for_one`: each owns its own state and re-reads the truth
  on restart):

    * the ETS projection workers (ADR-041) — Browse, ContinueWatching,
      Detail, HeroCandidates, RecentlyAdded, Search — not under `:test`
      (`MediaCentaur.Cache.workers_run?/0`);
    * `Progress.Worker`, the watch-progress ETS owner, likewise;
    * `BroadcastCoalescer`, `MediaFileAvailability`, `AbsenceSweeper`,
      `FileEventHandler`;
    * `Inbound`, the entity-publication listener, in instances that run
      background services.
  """
  use Supervisor

  alias MediaCentaur.Cache
  alias MediaCentaur.Library
  alias MediaCentaur.Settings.Config

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    workers? = Cache.workers_run?()
    background? = Config.get(:background_services)

    children =
      if(workers?,
        do: [
          {Cache.Worker, context: Library.Views.Browse},
          {Cache.Worker, context: Library.Views.ContinueWatching},
          {Cache.Worker, context: Library.Views.Detail},
          {Cache.Worker, context: Library.Views.HeroCandidates},
          {Cache.Worker, context: Library.Views.RecentlyAdded},
          {Cache.Worker, context: Library.Views.Search},
          Library.Progress.Worker
        ],
        else: []
      ) ++
        [
          Library.BroadcastCoalescer,
          Library.MediaFileAvailability,
          Library.AbsenceSweeper,
          Library.FileEventHandler
        ] ++ if(background?, do: [Library.Inbound], else: [])

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end
end
