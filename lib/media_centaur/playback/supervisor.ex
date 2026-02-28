defmodule MediaCentaur.Playback.Supervisor do
  @moduledoc """
  Groups the Playback Manager and SessionSupervisor under a single supervisor.

  Uses `:rest_for_one` strategy: if SessionSupervisor crashes, Manager restarts
  (session refs are invalid). If Manager crashes, SessionSupervisor and any active
  MpvSession survive — the restarted Manager rediscovers the running session.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      MediaCentaur.Playback.SessionSupervisor,
      MediaCentaur.Playback.Manager
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
