defmodule MediaCentaur.Acquisition.Pursuits.Events.ZeroSeedersConfirmed do
  @moduledoc "Recorded when the Watcher confirms zero seeders sustained beyond threshold."

  use MediaCentaur.Acquisition.Pursuits.Events.Define,
    kind: "zero_seeders_confirmed",
    payload_keys: [:window_hours]
end
