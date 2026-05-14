defmodule MediaCentarr.Acquisition.Pursuits.Events.SearchStarted do
  @moduledoc """
  Recorded when a Prowlarr search begins for a pursuit.

  - `query` — the literal Prowlarr query string the worker dispatched
    (one expanded term, e.g. "Sample Show S01E03"). Surfaced verbatim
    in the timeline so the user can see what was searched.
  """

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "search_started",
    payload_keys: [:query]
end
