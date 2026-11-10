defmodule MediaCentaur.SelfUpdate.Supervisor do
  @moduledoc """
  SelfUpdate's processes: `Updater` (download, stage, hand off) and
  `AutoApply` (apply a detected update when the screen is idle).
  Independent, `:one_for_one`.
  """
  use Supervisor

  alias MediaCentaur.SelfUpdate

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [SelfUpdate.Updater, SelfUpdate.AutoApply]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end
end
