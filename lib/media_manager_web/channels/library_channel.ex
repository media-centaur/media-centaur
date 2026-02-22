defmodule MediaManagerWeb.LibraryChannel do
  @moduledoc """
  Serves the media library over Phoenix Channels. Sends the full entity list
  on join and pushes incremental adds/updates/removals via PubSub.
  """
  use Phoenix.Channel

  alias MediaManager.Library.Entity
  alias MediaManager.Playback.ProgressSummary
  alias MediaManager.Serializer

  @impl true
  def join("library", _params, socket) do
    Phoenix.PubSub.subscribe(MediaManager.PubSub, "library:updates")
    entities = build_entity_list()
    known_ids = MapSet.new(entities, fn entity -> entity["@id"] end)
    socket = assign(socket, :known_entity_ids, known_ids)
    {:ok, %{entities: entities}, socket}
  end

  @impl true
  def handle_info({:entities_changed, entity_ids}, socket) do
    known_ids = socket.assigns.known_entity_ids

    new_known_ids =
      Enum.reduce(entity_ids, known_ids, fn entity_id, acc ->
        case load_entity_payload(entity_id) do
          nil ->
            if MapSet.member?(acc, entity_id) do
              push(socket, "library:entity_removed", %{"@id" => entity_id})
            end

            MapSet.delete(acc, entity_id)

          payload ->
            if MapSet.member?(acc, entity_id) do
              push(socket, "library:entity_updated", payload)
            else
              push(socket, "library:entity_added", payload)
            end

            MapSet.put(acc, entity_id)
        end
      end)

    {:noreply, assign(socket, :known_entity_ids, new_known_ids)}
  end

  @impl true
  def handle_info(:library_changed, socket) do
    # Backward compatibility for any code still sending the old message
    entities = build_entity_list()
    known_ids = MapSet.new(entities, fn entity -> entity["@id"] end)
    for payload <- entities, do: push(socket, "library:entity_updated", payload)
    {:noreply, assign(socket, :known_entity_ids, known_ids)}
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
