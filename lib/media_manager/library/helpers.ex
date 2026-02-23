defmodule MediaManager.Library.Helpers do
  @moduledoc false

  alias MediaManager.Library.Entity

  @doc """
  Loads an entity with all associations. Returns `{:ok, entity}` or `{:error, :not_found}`.
  """
  def load_entity(entity_id) do
    case Ash.get(Entity, entity_id, action: :with_associations) do
      {:ok, entity} -> {:ok, entity}
      {:error, _} -> {:error, :not_found}
    end
  end

  @doc """
  Broadcasts `{:entities_changed, entity_ids}` to the `"library:updates"` PubSub topic.
  """
  def broadcast_entities_changed(entity_ids) do
    Phoenix.PubSub.broadcast(
      MediaManager.PubSub,
      "library:updates",
      {:entities_changed, entity_ids}
    )
  end
end
