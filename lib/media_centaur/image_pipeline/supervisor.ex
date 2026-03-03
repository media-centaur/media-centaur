defmodule MediaCentaur.ImagePipeline.Supervisor do
  @moduledoc """
  Groups ImagePipeline.Stats, ImagePipeline, and RetryScheduler under a single supervisor.

  Uses `:rest_for_one` strategy: Stats crash cascades to ImagePipeline and
  RetryScheduler (clean telemetry re-attach). RetryScheduler crash does not
  affect Stats or ImagePipeline — a fresh retry budget is intentionally
  desirable after crash.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    start_pipeline? = Keyword.get(opts, :start_pipeline, true)

    children =
      Enum.reject(
        [
          MediaCentaur.ImagePipeline.Stats,
          if(start_pipeline?, do: MediaCentaur.ImagePipeline),
          if(start_pipeline?, do: MediaCentaur.ImagePipeline.RetryScheduler)
        ],
        &is_nil/1
      )

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 30)
  end
end
