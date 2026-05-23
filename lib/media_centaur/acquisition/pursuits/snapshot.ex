defmodule MediaCentaur.Acquisition.Pursuits.Snapshot do
  @moduledoc "Frozen view of a pursuit's world at one instant, consumed by Policy."

  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Thresholds}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Downloads.QueueItem

  @enforce_keys [:pursuit, :current_target, :queue_state, :now, :thresholds]
  defstruct [
    :pursuit,
    :current_target,
    :queue_state,
    :now,
    :thresholds,
    :stall_observed?,
    :stall_window_elapsed?,
    :zero_seeders_observed?,
    :zero_seeders_window_elapsed?
  ]

  @type queue_state :: [QueueItem.t()] | :unknown

  @type t :: %__MODULE__{
          pursuit: Pursuit.t(),
          current_target: Target.t() | nil,
          queue_state: queue_state(),
          now: DateTime.t(),
          thresholds: Thresholds.t(),
          stall_observed?: boolean() | nil,
          stall_window_elapsed?: boolean() | nil,
          zero_seeders_observed?: boolean() | nil,
          zero_seeders_window_elapsed?: boolean() | nil
        }
end
