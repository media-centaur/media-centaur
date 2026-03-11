defmodule MediaCentaur.Library.Helpers do
  @moduledoc false

  alias MediaCentaur.Library
  alias MediaCentaur.Topics

  @doc """
  Loads an entity with all associations. Returns `{:ok, entity}` or `{:error, :not_found}`.
  """
  def load_entity(entity_id) do
    case Library.get_entity_with_associations(entity_id) do
      {:ok, entity} -> {:ok, entity}
      {:error, _} -> {:error, :not_found}
    end
  end

  @doc """
  Extracts unique non-nil entity IDs from a list of records with an `entity_id` field.
  """
  def unique_entity_ids(records) do
    records
    |> MapSet.new(& &1.entity_id)
    |> MapSet.delete(nil)
    |> MapSet.to_list()
  end

  @doc """
  Broadcasts `{:entities_changed, entity_ids}` to the `"library:updates"` PubSub topic.
  """
  def broadcast_entities_changed([]), do: :ok

  def broadcast_entities_changed(entity_ids) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.library_updates(),
      {:entities_changed, entity_ids}
    )
  end
end
