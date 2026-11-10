defmodule MediaCentaur.Status.Supervisor do
  @moduledoc """
  The Status page's two projections (`Views.Overview`, `Views.Storage`),
  primed asynchronously — both run disk probes (`df`, per-image checks)
  that must never block boot — and refreshed on an interval, the drift net
  for slices with no source event. Not under `:test`
  (`MediaCentaur.Cache.workers_run?/0`).
  """
  use Supervisor

  alias MediaCentaur.Cache
  alias MediaCentaur.Status

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    workers? = Cache.workers_run?()

    children =
      if workers? do
        [
          {Cache.Worker,
           context: Status.Views.Overview, prime: :async, refresh_interval_ms: to_timeout(minute: 10)},
          {Cache.Worker,
           context: Status.Views.Storage, prime: :async, refresh_interval_ms: to_timeout(minute: 5)}
        ]
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end
end
