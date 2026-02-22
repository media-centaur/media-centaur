defmodule MediaManagerWeb.LibraryChannel do
  @moduledoc """
  Serves the media library over Phoenix Channels. Streams the full entity list
  in batches on join, then pushes incremental updates via PubSub.
  """
  use Phoenix.Channel

  alias MediaManager.Library.Entity
  alias MediaManager.Playback.ProgressSummary
  alias MediaManager.Serializer

  @batch_size 50

  @impl true
  def join("library", _params, socket) do
    Phoenix.PubSub.subscribe(MediaManager.PubSub, "library:updates")
    send(self(), :sync_library)
    {:ok, %{}, assign(socket, :known_entity_ids, MapSet.new())}
  end

  @impl true
  def handle_info(:sync_library, socket) do
    entities = build_entity_list()
    known_ids = MapSet.new(entities, fn entity -> entity["@id"] end)

    entities
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      push(socket, "library:entities", %{entities: batch})
    end)

    push(socket, "library:sync_complete", %{})

    {:noreply, assign(socket, :known_entity_ids, known_ids)}
  end

  @impl true
  def handle_info({:entities_changed, entity_ids}, socket) do
    known_ids = socket.assigns.known_entity_ids

    {updated, removed, new_known_ids} =
      Enum.reduce(entity_ids, {[], [], known_ids}, fn entity_id, {upd, rem, ids} ->
        case load_entity_payload(entity_id) do
          nil ->
            if MapSet.member?(ids, entity_id) do
              {upd, [entity_id | rem], MapSet.delete(ids, entity_id)}
            else
              {upd, rem, ids}
            end

          payload ->
            {[payload | upd], rem, MapSet.put(ids, entity_id)}
        end
      end)

    if updated != [], do: push(socket, "library:entities", %{entities: Enum.reverse(updated)})
    if removed != [], do: push(socket, "library:entities_removed", %{ids: Enum.reverse(removed)})

    {:noreply, assign(socket, :known_entity_ids, new_known_ids)}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp load_entity_payload(entity_id) do
    case Ash.get(Entity, entity_id, action: :with_associations) do
      {:ok, entity} -> serialize_with_progress(entity)
      {:error, _} -> nil
    end
  end

  defp build_entity_list do
    Entity
    |> Ash.read!(action: :with_associations)
    |> Enum.map(&serialize_with_progress/1)
  end

  defp serialize_with_progress(entity) do
    progress_records = entity.watch_progress || []
    serialized = Serializer.serialize_entity(entity)
    progress = ProgressSummary.compute(entity, progress_records)
    Map.put(serialized, "progress", progress)
  end
end
