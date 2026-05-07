defmodule MediaCentarr.Acquisition.Pursuits.Events.DownloadStarted do
  @moduledoc "Recorded when the download client picks up a grabbed release."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "download_started",
    payload_keys: [:client, :infohash]
end
