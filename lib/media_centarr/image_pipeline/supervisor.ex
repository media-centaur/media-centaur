defmodule MediaCentarr.ImagePipeline.Supervisor do
  @moduledoc """
  Groups ImagePipeline.Stats, ImagePipeline, and RetryScheduler under a single supervisor.

  Uses `:rest_for_one` strategy: Stats crash cascades to ImagePipeline and
  RetryScheduler (clean telemetry re-attach). RetryScheduler crash does not
  affect Stats or ImagePipeline — a fresh retry budget is intentionally
  desirable after crash.
  """
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      MediaCentarr.ImagePipeline.Stats,
      MediaCentarr.ImagePipeline,
      MediaCentarr.ImagePipeline.RetryScheduler
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 30)
  end

  @doc "Starts the ImagePipeline Broadway process and RetryScheduler."
  def start_pipeline do
    Supervisor.restart_child(__MODULE__, MediaCentarr.ImagePipeline)
    Supervisor.restart_child(__MODULE__, MediaCentarr.ImagePipeline.RetryScheduler)
  end

  @doc "Stops the ImagePipeline Broadway process and RetryScheduler."
  def stop_pipeline do
    Supervisor.terminate_child(__MODULE__, MediaCentarr.ImagePipeline.RetryScheduler)
    Supervisor.terminate_child(__MODULE__, MediaCentarr.ImagePipeline)
  end

  @doc "Returns true if the ImagePipeline Broadway process is running."
  def pipeline_running? do
    __MODULE__
    |> Supervisor.which_children()
    |> Enum.any?(fn {id, pid, _, _} -> id == MediaCentarr.ImagePipeline and is_pid(pid) end)
  end
end
