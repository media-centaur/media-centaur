defmodule MediaCentaur.Acquisition.Pursuits.Events.StallConfirmed do
  @moduledoc "Recorded when the Watcher confirms a long-horizon stall."

  use MediaCentaur.Acquisition.Pursuits.Events.Define,
    kind: "stall_confirmed",
    payload_keys: [:window_hours, :throughput_avg_bps]
end
