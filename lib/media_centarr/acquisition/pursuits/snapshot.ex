defmodule MediaCentarr.Acquisition.Pursuits.Snapshot do
  @moduledoc "Frozen view of a pursuit's world at one instant, consumed by Policy."

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.QueueItem

  @enforce_keys [:pursuit, :latest_grab, :queue_state, :now]
  defstruct [:pursuit, :latest_grab, :queue_state, :now]

  @type queue_state :: [QueueItem.t()] | :unknown

  @type t :: %__MODULE__{
          pursuit: Pursuit.t(),
          latest_grab: Grab.t() | nil,
          queue_state: queue_state(),
          now: DateTime.t()
        }
end
