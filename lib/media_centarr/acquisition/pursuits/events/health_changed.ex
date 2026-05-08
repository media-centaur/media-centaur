defmodule MediaCentarr.Acquisition.Pursuits.Events.HealthChanged do
  @moduledoc """
  Recorded when a pursuit's tracked queue item changes state or health.

  `from_state`/`to_state` are the qBittorrent transport state strings
  (`"queued"`, `"downloading"`, `"stalled"`, `"completed"`, ...).
  `from_health`/`to_health` are the Media Centarr classification strings
  (`"healthy"`, `"slow"`, `"soft_stall"`, `"frozen"`, ...). Either axis
  may have changed; the other axis is recorded too so the timeline entry
  carries the full context.
  """

  use MediaCentarr.Acquisition.Pursuits.Events.Define,
    kind: "health_changed",
    payload_keys: [:from_state, :to_state, :from_health, :to_health]
end
