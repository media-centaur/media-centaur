defmodule MediaCentaur.Acquisition.Pursuits.Events.PursuitCancelled do
  @moduledoc "Recorded when a pursuit is cancelled by a user."

  use MediaCentaur.Acquisition.Pursuits.Events.Define,
    kind: "pursuit_cancelled",
    payload_keys: [:cancelled_by, :reason]
end
