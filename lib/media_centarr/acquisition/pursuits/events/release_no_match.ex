defmodule MediaCentarr.Acquisition.Pursuits.Events.ReleaseNoMatch do
  @moduledoc "Recorded when a Prowlarr search finds no acceptable release."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "release_no_match",
    payload_keys: [:searched_count, :reason]
end
