defmodule MediaCentaur.Watcher.Dirs do
  @moduledoc """
  The watching flag's children (`start_watchers`, under
  `MediaCentaur.Watcher.FlagSupervisor`): the per-directory watchers and
  the image-dir monitors under their DynamicSupervisors, and the controller
  that keeps both sets equal to the configured media dirs. The whole
  subtree exists only while watching is on; with it off there is no
  watcher, no monitor and no process reacting to a media-dir edit.

  `:rest_for_one`: the controller sits last, so a crash of either
  DynamicSupervisor restarts it and it relaunches the configured set.
  """
  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      {DynamicSupervisor, name: MediaCentaur.Watcher.DynamicSupervisor, strategy: :one_for_one},
      {DynamicSupervisor,
       name: MediaCentaur.Watcher.DirMonitor.DynamicSupervisor, strategy: :one_for_one},
      MediaCentaur.Watcher.Dirs.Controller
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 60)
  end
end
