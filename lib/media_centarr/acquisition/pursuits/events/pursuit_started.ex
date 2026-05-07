defmodule MediaCentarr.Acquisition.Pursuits.Events.PursuitStarted do
  @moduledoc "Recorded when a pursuit is created."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "pursuit_started",
    payload_keys: [:origin]
end
