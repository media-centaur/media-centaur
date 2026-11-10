defmodule MediaCentaurWeb.Supervisor do
  @moduledoc """
  The web layer's processes: the `ShellBadges` projection worker (sidebar
  badge counts; not under `:test`, `MediaCentaur.Cache.workers_run?/0`),
  `DownloadsLive.SearchSession` (the one acquisition search session) and
  the `Endpoint`, last, so a request never finds the others missing.
  `:rest_for_one`: the Endpoint restarts with what it reads.
  """
  use Supervisor

  alias MediaCentaur.Cache

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    workers? = Cache.workers_run?()

    children =
      if(workers?, do: [{Cache.Worker, context: MediaCentaurWeb.ShellBadges}], else: []) ++
        [MediaCentaurWeb.DownloadsLive.SearchSession, MediaCentaurWeb.Endpoint]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 30)
  end
end
