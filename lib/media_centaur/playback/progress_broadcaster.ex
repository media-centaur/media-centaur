defmodule MediaCentaur.Playback.ProgressBroadcaster do
  @moduledoc """
  Broadcasts entity progress updates to the playback PubSub topic.

  Loads the entity with progress, computes summary/resume/child targets,
  and broadcasts to `"playback:events"`. Used by MpvSession (after persisting
  progress) and LibraryLive (after toggling watched status).
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format

  @doc """
  Loads entity progress and broadcasts an `:entity_progress_updated` message.

  `season_number` and `episode_number` identify the specific item that changed,
  used for computing the child targets delta.
  """
  def broadcast(entity_id, season_number, episode_number) do
    case MediaCentaur.Library.get_entity_with_progress(entity_id) do
      {:ok, entity} ->
        progress_records = entity.watch_progress || []
        summary = MediaCentaur.Playback.ProgressSummary.compute(entity, progress_records)
        resume_target = MediaCentaur.Playback.ResumeTarget.compute(entity, progress_records)

        child_targets_delta =
          MediaCentaur.Playback.ResumeTarget.compute_child_target_delta(
            entity,
            progress_records,
            season_number,
            episode_number
          )

        changed_record =
          Enum.find(progress_records, fn record ->
            record.season_number == season_number && record.episode_number == episode_number
          end)

        Log.info(:playback, "broadcast progress — #{Format.short_id(entity_id)}")

        Phoenix.PubSub.broadcast(
          MediaCentaur.PubSub,
          MediaCentaur.Topics.playback_events(),
          {:entity_progress_updated,
           %{
             entity_id: entity_id,
             summary: summary,
             resume_target: resume_target,
             child_targets_delta: child_targets_delta,
             changed_record: changed_record,
             last_activity_at: DateTime.utc_now()
           }}
        )

      {:error, _} ->
        :ok
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
