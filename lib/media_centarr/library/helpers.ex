defmodule MediaCentarr.Library.Helpers do
  @moduledoc false

  alias MediaCentarr.Library.Events
  alias MediaCentarr.Library.Events.EntitiesChanged

  @doc """
  Broadcasts an `EntitiesChanged` event on the `"library:updates"` topic.

  In production/dev, routes through the coalescer (200ms batching window).
  In `:test`, broadcasts immediately so tests stay isolated and deterministic
  — concurrent tests must not see each other's broadcasts via shared coalescer
  state. The coalescer's own behavior is exercised directly in
  `MediaCentarr.Library.BroadcastCoalescerTest`.
  """
  def broadcast_entities_changed([]), do: :ok

  def broadcast_entities_changed(entity_ids) do
    if Application.get_env(:media_centarr, :coalesce_broadcasts?, true) do
      MediaCentarr.Library.BroadcastCoalescer.enqueue(entity_ids)
    else
      Events.broadcast(%EntitiesChanged{entity_ids: entity_ids})
    end
  end
end
