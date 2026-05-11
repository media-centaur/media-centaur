defmodule MediaCentarr.Acquisition.Pursuits.Events.PursuitReSearched do
  @moduledoc "Recorded when a user manually re-arms the pursuit's underlying grab."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "pursuit_re_searched",
    payload_keys: []
end
