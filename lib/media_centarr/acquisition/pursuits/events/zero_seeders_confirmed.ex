defmodule MediaCentarr.Acquisition.Pursuits.Events.ZeroSeedersConfirmed do
  @moduledoc "Recorded when the Watcher confirms zero seeders sustained beyond threshold."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "zero_seeders_confirmed",
    payload_keys: [:window_hours]
end
