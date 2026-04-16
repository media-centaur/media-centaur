defmodule MediaCentarr.Library.Helpers do
  @moduledoc false

  alias MediaCentarr.Topics

  @doc """
  Broadcasts `{:entities_changed, entity_ids}` to the `"library:updates"` PubSub topic.
  """
  def broadcast_entities_changed([]), do: :ok

  def broadcast_entities_changed(entity_ids) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.library_updates(),
      {:entities_changed, entity_ids}
    )
  end
end
