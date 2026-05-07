defmodule MediaCentarr.Acquisition.Pursuits.Events.SearchStarted do
  @moduledoc "Recorded when a Prowlarr search begins for a pursuit."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "search_started",
    payload_keys: []
end
