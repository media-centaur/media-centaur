defmodule MediaCentaur.Pipeline.Supervisor do
  @moduledoc """
  Groups Pipeline.Stats and Pipeline under a single supervisor.

  Uses `:rest_for_one` strategy: if Stats crashes, Pipeline restarts (clean
  telemetry re-attach). Pipeline crash does not affect Stats — counters
  continue to reflect the last known state until the restarted Pipeline
  emits new telemetry events.
  """
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      MediaCentaur.Pipeline.Stats,
      MediaCentaur.Pipeline
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 30)
  end

  @doc "Starts the Pipeline Broadway process (no-op if already running)."
  def start_pipeline do
    Supervisor.restart_child(__MODULE__, MediaCentaur.Pipeline)
  end

  @doc "Stops the Pipeline Broadway process (no-op if already stopped)."
  def stop_pipeline do
    Supervisor.terminate_child(__MODULE__, MediaCentaur.Pipeline)
  end

  @doc "Returns true if the Pipeline Broadway process is running."
  def pipeline_running? do
    __MODULE__
    |> Supervisor.which_children()
    |> Enum.any?(fn {id, pid, _, _} -> id == MediaCentaur.Pipeline and is_pid(pid) end)
  end
end
