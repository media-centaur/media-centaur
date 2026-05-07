defmodule MediaCentarr.Acquisition.Pursuits.Events.UserDecisionRequested do
  @moduledoc "Recorded when a pursuit transitions to needs_decision."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "user_decision_requested",
    payload_keys: [:prompt]
end
