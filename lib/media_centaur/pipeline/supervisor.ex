defmodule MediaCentaur.Pipeline.Supervisor do
  @moduledoc """
  Groups Pipeline.Stats and Pipeline under a single supervisor.

  Uses `:rest_for_one` strategy: if Stats crashes, Pipeline restarts (clean
  telemetry re-attach). Pipeline crash does not affect Stats — counters
  continue to reflect the last known state until the restarted Pipeline
  emits new telemetry events.
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
          MediaCentaur.Pipeline.Stats,
          if(start_pipeline?, do: MediaCentaur.Pipeline)
        ],
        &is_nil/1
      )

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 30)
  end
end
