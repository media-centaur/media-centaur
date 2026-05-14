defmodule MediaCentarr.Acquisition.Pursuits.Events.UserDecisionRequested do
  @moduledoc "Recorded when a pursuit's `awaiting_decision_at` flag is set (system asks the user to pick)."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "user_decision_requested",
    payload_keys: [:prompt]
end
