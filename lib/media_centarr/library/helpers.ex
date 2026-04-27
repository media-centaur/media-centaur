defmodule MediaCentarr.Library.Helpers do
  @moduledoc false

  @doc """
  Broadcasts `{:entities_changed, entity_ids}` to the `"library:updates"` PubSub topic.
  """
  def broadcast_entities_changed([]), do: :ok

  def broadcast_entities_changed(entity_ids) do
    MediaCentarr.Library.BroadcastCoalescer.enqueue(entity_ids)
  end
end
