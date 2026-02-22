defmodule MediaManagerWeb.LibraryChannel do
  use Phoenix.Channel

  alias MediaManager.Library.Entity
  alias MediaManager.Playback.ProgressSummary
  alias MediaManager.Serializer

  @impl true
  def join("library", _params, socket) do
    Phoenix.PubSub.subscribe(MediaManager.PubSub, "library:updates")
    entities = build_entity_list()
    {:ok, %{entities: entities}, socket}
  end

  @impl true
  def handle_info(:library_changed, socket) do
    entities = build_entity_list()

    for entity_payload <- entities do
      push(socket, "library:entity_updated", entity_payload)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp build_entity_list do
    entities = Ash.read!(Entity, action: :with_associations)

    Enum.map(entities, fn entity ->
      progress_records = entity.watch_progress || []
      serialized = Serializer.serialize_entity(entity)
      progress = ProgressSummary.compute(entity, progress_records)
      Map.put(serialized, "progress", progress)
    end)
  end
end
