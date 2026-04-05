defmodule MediaCentaur.Playback.ProgressBroadcaster do
  @moduledoc """
  Broadcasts entity progress updates to the playback PubSub topic.

  Loads the entity with progress, computes summary/resume/child targets,
  and broadcasts to `"playback:events"`. Used by MpvSession (after persisting
  progress) and LibraryLive (after toggling watched status).
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.{EntityShape, TypeResolver}

  @doc """
  Loads entity progress and broadcasts an `:entity_progress_updated` message.

  `changed_record` is the specific `WatchProgress` record whose change triggered
  this broadcast. Subscribers (LiveViews) use it to keep their in-memory
  per-entity progress_records list in sync with the authoritative summary.
  Pass `nil` only when the caller truly has no single record to report (e.g.
  a bulk recomputation).
  """
  def broadcast(entity_id, changed_record \\ nil) do
    case resolve_entity_with_progress(entity_id) do
      {:ok, entity, progress_records} ->
        summary = MediaCentaur.Playback.ProgressSummary.compute(entity, progress_records)
        resume_target = MediaCentaur.Playback.ResumeTarget.compute(entity, progress_records)

        Log.info(:playback, "broadcast progress — #{Format.short_id(entity_id)}")

        Phoenix.PubSub.broadcast(
          MediaCentaur.PubSub,
          MediaCentaur.Topics.playback_events(),
          {:entity_progress_updated,
           %{
             entity_id: entity_id,
             summary: summary,
             resume_target: resume_target,
             child_targets_delta: nil,
             changed_record: changed_record,
             last_activity_at: DateTime.utc_now()
           }}
        )

      :not_found ->
        :ok
    end
  end

  @with_associations_preloads [
    tv_series: Library.tv_series_full_preloads(),
    movie_series: Library.movie_series_full_preloads(),
    movie: Library.movie_full_preloads(),
    video_object: Library.video_object_full_preloads()
  ]

  defp resolve_entity_with_progress(id) do
    case TypeResolver.resolve(id, preload: @with_associations_preloads) do
      {:ok, type, record} ->
        progress = EntityShape.extract_progress(record, type)
        normalized = EntityShape.normalize(record, type)
        {:ok, normalized, progress}

      :not_found ->
        :not_found
    end
  end

  @doc """
  Broadcasts an `:extra_progress_updated` message for a specific extra.

  Simpler than entity broadcast — no summary/resume recomputation needed.
  Loads the current ExtraProgress record and broadcasts it.
  """
  def broadcast_extra(entity_id, extra_id) do
    progress =
      case MediaCentaur.Library.get_extra_progress_by_extra(extra_id) do
        {:ok, record} -> record
        _ -> nil
      end

    Log.info(:playback, "broadcast extra progress — #{Format.short_id(extra_id)}")

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.playback_events(),
      {:extra_progress_updated,
       %{
         entity_id: entity_id,
         extra_id: extra_id,
         progress: progress
       }}
    )
  end
end
