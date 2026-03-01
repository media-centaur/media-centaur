defmodule MediaCentaur.Library.Helpers do
  @moduledoc false

  alias MediaCentaur.Library.{Entity, WatchedFile}

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
  Returns a MapSet of entity IDs that have WatchedFiles but all are absent.
  These entities should be excluded from the library view.
  """
  def entity_ids_all_absent do
    WatchedFile
    |> Ash.read!()
    |> Enum.group_by(& &1.entity_id)
    |> Enum.filter(fn {_entity_id, files} ->
      Enum.all?(files, &(&1.state == :absent))
    end)
    |> Enum.map(fn {entity_id, _} -> entity_id end)
    |> MapSet.new()
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
