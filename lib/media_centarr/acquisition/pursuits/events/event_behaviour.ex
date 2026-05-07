defmodule MediaCentarr.Acquisition.Pursuits.Events.EventBehaviour do
  @moduledoc """
  Behaviour every typed pursuit-event struct module implements.

  Each struct is the in-memory shape subscribers receive. The DB row
  stores `kind` (from `kind/0`) and `payload` (from `to_payload/1`); a
  cold replay rebuilds the struct via `from_payload/1`.

  The struct itself MUST carry the three envelope fields the persistence
  layer needs: `pursuit_id`, `pursuit_title`, `occurred_at`. Everything
  else is event-kind-specific and serialized into the `payload` map.
  """

  @callback kind() :: String.t()
  @callback to_payload(struct()) :: map()
  @callback from_payload(map()) :: struct()
end
