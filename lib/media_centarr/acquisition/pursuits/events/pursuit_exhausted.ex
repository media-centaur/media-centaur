defmodule MediaCentarr.Acquisition.Pursuits.Events.PursuitExhausted do
  @moduledoc "Recorded when a pursuit gives up after exhausting its alternatives."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "pursuit_exhausted",
    payload_keys: [:attempt_count, :reason]
end
