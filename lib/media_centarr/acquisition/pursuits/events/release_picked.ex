defmodule MediaCentarr.Acquisition.Pursuits.Events.ReleasePicked do
  @moduledoc "Recorded when Prowlarr accepts a release for a pursuit."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "release_picked",
    payload_keys: [:release_title, :guid, :indexer, :quality, :size_bytes]
end
