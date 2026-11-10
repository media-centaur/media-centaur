defmodule MediaCentaur.Review.Supervisor do
  @moduledoc """
  Review's listeners, in instances that run background services: `Intake`
  (the pipeline's needs-review outcomes) and `FileEventHandler` (removed
  files). Independent, `:one_for_one`.
  """
  use Supervisor

  alias MediaCentaur.Review
  alias MediaCentaur.Settings.Config

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    background? = Config.get(:background_services)
    children = if(background?, do: [Review.Intake, Review.FileEventHandler], else: [])

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end
end
