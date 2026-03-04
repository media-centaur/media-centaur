defmodule MediaCentaur.Library.Helpers do
  @moduledoc false

  alias MediaCentaur.Library

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
  Returns a MapSet of entity IDs that have WatchedFiles but all are absent.
  These entities should be excluded from the library view.
  """
  def entity_ids_all_absent do
    Library.list_entities_all_files_absent!()
    |> MapSet.new(& &1.id)
  end

  @doc """
  Returns a MapSet of entity IDs (from the given list) where every WatchedFile is absent.
  Only queries watched files for the specified entity IDs.
  """
  def entity_ids_all_absent_for([]), do: MapSet.new()

  def entity_ids_all_absent_for(entity_ids) do
    Library.list_entities_all_files_absent!(query: [filter: [id: [in: entity_ids]]])
    |> MapSet.new(& &1.id)
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
      "library:updates",
      {:entities_changed, entity_ids}
    )
  end
end
