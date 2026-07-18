defmodule MediaCentaur.Status.Views.StorageSnapshot do
  @moduledoc """
  View-model for the Status page's storage picture: per-mount-point drive
  capacity (`MediaCentaur.Storage.measure_all/0`), the at-risk absence
  summary, and per-media-dir reachability.

  `dir_health` reports filesystem reachability of each configured media
  dir and its image cache. Note the deliberate overlap with
  `Library.Availability.dir_status/0` (the watcher-driven availability
  state): Availability answers "does the library treat this dir as
  present?", `dir_health` answers "does the filesystem say the paths
  exist right now?" — the Status page shows the latter precisely so an
  operator can spot disagreement. Unifying the two representations is
  recorded in `campaigns/instant-navigation.md` as a deferred item.
  """

  alias MediaCentaur.Storage

  @type dir_health :: %{
          dir: String.t(),
          dir_exists: boolean(),
          image_dir: String.t(),
          image_dir_exists: boolean()
        }

  @type t :: %__MODULE__{
          drives: [Storage.drive()],
          at_risk: map(),
          dir_health: [dir_health()],
          measured_at: DateTime.t()
        }

  @enforce_keys [:drives, :at_risk, :dir_health, :measured_at]
  defstruct [:drives, :at_risk, :dir_health, :measured_at]
end
