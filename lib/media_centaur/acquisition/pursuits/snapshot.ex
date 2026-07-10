defmodule MediaCentaur.Acquisition.Pursuits.Snapshot do
  @moduledoc """
  Frozen view of one unit's world at one instant, consumed by Policy.

  The watcher loop runs per unit (ADR-055): the unit carries the
  attempt thread and observation timestamps; the pursuit rides along
  for the goal-level facts Policy still needs (lifecycle state,
  criteria).
  """

  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Thresholds, Unit}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Downloads.QueueItem

  @enforce_keys [:pursuit, :unit, :current_target, :queue_state, :now, :thresholds]
  defstruct [
    :pursuit,
    :unit,
    :current_target,
    :queue_state,
    :now,
    :thresholds,
    :stall_observed?,
    :stall_window_elapsed?,
    :zero_seeders_observed?,
    :zero_seeders_window_elapsed?,
    # Client-reported terminal failure of the unit's tracked download
    # (SABnzbd's par2-unrepairable / unpack-failed). Deterministic — no
    # observation window; Policy pivots immediately.
    :download_failed?
  ]

  @type queue_state :: [QueueItem.t()] | :unknown

  @type t :: %__MODULE__{
          pursuit: Pursuit.t(),
          unit: Unit.t(),
          current_target: Target.t() | nil,
          queue_state: queue_state(),
          now: DateTime.t(),
          thresholds: Thresholds.t(),
          stall_observed?: boolean() | nil,
          stall_window_elapsed?: boolean() | nil,
          zero_seeders_observed?: boolean() | nil,
          zero_seeders_window_elapsed?: boolean() | nil,
          download_failed?: boolean() | nil
        }
end
