defmodule MediaCentarr.Acquisition.Pursuits.Events.ReleaseNoMatch do
  @moduledoc """
  Recorded when a Prowlarr search finds no acceptable release.

  - `query` — the literal Prowlarr query string that came back empty,
    so the timeline row can name what was tried.
  """

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "release_no_match",
    payload_keys: [:searched_count, :reason, :query]
end
