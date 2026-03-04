defmodule MediaCentaurWeb.LibraryChannel do
  @moduledoc """
  Serves the media library over Phoenix Channels. Streams the full entity list
  in batches on join, then pushes incremental updates via PubSub.
  """
  use Phoenix.Channel
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Helpers
  alias MediaCentaur.LastActivity
  alias MediaCentaur.Playback.{ProgressSummary, ResumeTarget}
  alias MediaCentaur.Serializer

  @batch_size 50

  @impl true
  def join("library", _params, socket) do
    Log.info(:channel, "library channel joined")
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
    send(self(), :sync_library)
    {:ok, %{}, assign(socket, :known_entity_ids, MapSet.new())}
  end

  @impl true
  def handle_info(:sync_library, socket) do
    entities = build_entity_list()
    known_ids = MapSet.new(entities, fn entity -> entity["@id"] end)

    push_batched(socket, "library:entities", entities, :entities)
    Log.info(:channel, "library sync complete, #{length(entities)} entities")
    push(socket, "library:sync_complete", %{})

    {:noreply, assign(socket, :known_entity_ids, known_ids)}
  end

  @impl true
  def handle_info({:entities_changed, entity_ids}, socket) do
    known_ids = socket.assigns.known_entity_ids
    payloads_by_id = load_entity_payloads(entity_ids)

    {updated, removed, new_known_ids} =
      Enum.reduce(entity_ids, {[], [], known_ids}, fn entity_id, {updated, removed, known} ->
        case Map.get(payloads_by_id, entity_id) do
          nil ->
            if MapSet.member?(known, entity_id) do
              {updated, [entity_id | removed], MapSet.delete(known, entity_id)}
            else
              {updated, removed, known}
            end

          payload ->
            {[payload | updated], removed, MapSet.put(known, entity_id)}
        end
      end)

    updated_list = Enum.reverse(updated)
    removed_list = Enum.reverse(removed)

    if updated_list != [] or removed_list != [] do
      Log.info(
        :channel,
        "entity changes: #{length(updated_list)} updated, #{length(removed_list)} removed"
      )
    end

    push_batched(socket, "library:entities", updated_list, :entities)
    push_batched(socket, "library:entities_removed", removed_list, :ids)

    {:noreply, assign(socket, :known_entity_ids, new_known_ids)}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp push_batched(_socket, _event, [], _key), do: :ok

  defp push_batched(socket, event, items, key) do
    items
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      push(socket, event, %{key => batch})
    end)
  end

  defp load_entity_payloads(entity_ids) do
    excluded = Helpers.entity_ids_all_absent_for(entity_ids)

    Library.list_entities_by_ids!(entity_ids)
    |> Enum.reject(fn entity -> MapSet.member?(excluded, entity.id) end)
    |> Map.new(fn entity -> {entity.id, serialize_with_progress(entity)} end)
  end

  defp build_entity_list do
    excluded = Helpers.entity_ids_all_absent()

    Library.list_entities_with_associations!()
    |> Enum.reject(fn entity -> MapSet.member?(excluded, entity.id) end)
    |> Enum.map(&serialize_with_progress/1)
  end

  defp serialize_with_progress(entity) do
    progress_records = entity.watch_progress || []
    serialized = Serializer.serialize_entity(entity)
    progress = ProgressSummary.compute(entity, progress_records)
    resume_target = ResumeTarget.compute(entity, progress_records)
    child_targets = ResumeTarget.compute_child_targets(entity, progress_records)
    last_activity_at = LastActivity.compute(entity)

    serialized
    |> Map.put("progress", progress)
    |> Map.put("resumeTarget", resume_target)
    |> Map.put("childTargets", child_targets)
    |> Map.put("lastActivityAt", format_timestamp(last_activity_at))
  end

  defp format_timestamp(nil), do: nil
  defp format_timestamp(datetime), do: DateTime.to_iso8601(datetime)
end
