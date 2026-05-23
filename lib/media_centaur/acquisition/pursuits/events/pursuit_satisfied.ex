defmodule MediaCentaur.Acquisition.Pursuits.Events.PursuitSatisfied do
  @moduledoc "Recorded when a pursuit closes successfully on a verified arrival."

  use MediaCentaur.Acquisition.Pursuits.Events.Define,
    kind: "pursuit_satisfied",
    payload_keys: [:final_target_id, :final_release_title]
end
