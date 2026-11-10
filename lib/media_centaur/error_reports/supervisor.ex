defmodule MediaCentaur.ErrorReports.Supervisor do
  @moduledoc """
  ErrorReports' processes: `Buckets` (the in-memory cache over the incident
  store) and, with durable diagnostics on, `ShutdownMonitor` (the
  unclean-shutdown marker). Independent, `:one_for_one`.
  """
  use Supervisor

  alias MediaCentaur.ErrorReports

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    durable? = Application.get_env(:media_centaur, :durable_diagnostics, false)
    children = [ErrorReports.Buckets] ++ if(durable?, do: [ErrorReports.ShutdownMonitor], else: [])

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end
end
