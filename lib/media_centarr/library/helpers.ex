defmodule MediaCentarr.Library.Helpers do
  @moduledoc false

  alias MediaCentarr.Topics

  @doc """
  Broadcasts `{:entities_changed, entity_ids}` to the `"library:updates"` PubSub topic.

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
      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        Topics.library_updates(),
        {:entities_changed, entity_ids}
      )

      :ok
    end
  end
end
