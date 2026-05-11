defmodule MediaCentarr.Acquisition.Pursuits.Events.TargetChanged do
  @moduledoc """
  Recorded when the pursuit pivots to a new target — either by the user
  clicking "Change Target" (replaces the old "re-search" affordance) or
  by `Commands.ChangeTarget` on any other code path.

  The `target_id` payload key is the **new** target the pursuit is now
  chasing. The previous target's row, if any, was marked `failed` in
  the same transaction.
  """

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "target_changed",
    payload_keys: [:target_id]
end
