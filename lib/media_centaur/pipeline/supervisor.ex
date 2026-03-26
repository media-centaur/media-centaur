defmodule MediaCentaur.Pipeline.Supervisor do
  @moduledoc """
  Groups Pipeline.Stats, Discovery, and Import under a single supervisor.

  Uses `:rest_for_one` strategy: if Stats crashes, both pipelines restart
  (clean telemetry re-attach). Pipeline crashes do not affect Stats —
  counters continue to reflect the last known state until the restarted
  pipeline emits new telemetry events.
  """
  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      MediaCentaur.Pipeline.Stats,
      MediaCentaur.Pipeline.Discovery,
      MediaCentaur.Pipeline.Import
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 30)
  end

  @doc "Starts both pipeline Broadway processes (no-op if already running)."
  def start_pipeline do
    Supervisor.restart_child(__MODULE__, MediaCentaur.Pipeline.Discovery)
    Supervisor.restart_child(__MODULE__, MediaCentaur.Pipeline.Import)
  end

  @doc "Stops both pipeline Broadway processes (no-op if already stopped)."
  def stop_pipeline do
    Supervisor.terminate_child(__MODULE__, MediaCentaur.Pipeline.Import)
    Supervisor.terminate_child(__MODULE__, MediaCentaur.Pipeline.Discovery)
  end

  @doc "Returns true if both pipeline Broadway processes are running."
  def pipeline_running? do
    children = Supervisor.which_children(__MODULE__)

    Enum.all?(
      [MediaCentaur.Pipeline.Discovery, MediaCentaur.Pipeline.Import],
      fn id ->
        Enum.any?(children, fn {child_id, pid, _, _} -> child_id == id and is_pid(pid) end)
      end
    )
  end
end
