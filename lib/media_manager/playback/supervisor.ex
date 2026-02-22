defmodule MediaManager.Playback.Supervisor do
  @moduledoc """
  Groups the Playback Manager and SessionSupervisor under a single supervisor.

  Uses `:one_for_all` strategy because the two children are tightly coupled:
  if SessionSupervisor crashes, Manager's session reference becomes invalid;
  if Manager crashes, the active session would be orphaned.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      MediaManager.Playback.SessionSupervisor,
      MediaManager.Playback.Manager
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
