defmodule MediaCentaur.Playback.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for MpvSession processes.
  Multiple sessions may run concurrently, one per entity.
  """
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_session(params) do
    DynamicSupervisor.start_child(__MODULE__, {MediaCentaur.Playback.MpvSession, params})
  end

  def terminate_session(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
