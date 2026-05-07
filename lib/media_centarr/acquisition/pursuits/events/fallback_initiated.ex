defmodule MediaCentarr.Acquisition.Pursuits.Events.FallbackInitiated do
  @moduledoc "Recorded when a fresh grab is enqueued with the previously-failed release excluded."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "fallback_initiated",
    payload_keys: [:previous_guid, :reason]
end
