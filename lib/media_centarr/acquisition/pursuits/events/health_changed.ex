defmodule MediaCentarr.Acquisition.Pursuits.Events.HealthChanged do
  @moduledoc "Recorded when a download crosses a Health classification threshold."

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "health_changed",
    payload_keys: [:from_state, :to_state]
end
