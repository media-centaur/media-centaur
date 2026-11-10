defmodule MediaCentaur.Acquisition.Supervisor do
  @moduledoc """
  Acquisition's listeners, in instances that run background services:
  `Reactor` (release-tracking and watchlist events), `Pursuits.InboundListener`
  and `Pursuits.QueueListener`. Independent, `:one_for_one`.
  """
  use Supervisor

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Settings.Config

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    background? = Config.get(:background_services)

    children =
      if background? do
        [Acquisition.Reactor, Acquisition.Pursuits.InboundListener, Acquisition.Pursuits.QueueListener]
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end
end
