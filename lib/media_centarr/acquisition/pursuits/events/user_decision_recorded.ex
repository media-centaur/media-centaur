defmodule MediaCentarr.Acquisition.Pursuits.Events.UserDecisionRecorded do
  @moduledoc "Recorded when the user picks an alternative in the decision card."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "user_decision_recorded",
    payload_keys: [:choice]
end
