defmodule MediaCentarr.Acquisition.Pursuits.Events.PursuitCancelled do
  @moduledoc "Recorded when a pursuit is cancelled by a user."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "pursuit_cancelled",
    payload_keys: [:cancelled_by, :reason]
end
