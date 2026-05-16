defmodule MediaCentarr.Playback.ProgressBroadcaster do
  @moduledoc """
  Broadcasts entity progress updates to the playback PubSub topic.

  Loads the entity with progress, computes summary/resume/child targets,
  and broadcasts to `"playback:events"`. Used by MpvSession (after persisting
  progress) and LibraryLive (after toggling watched status).
  """
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Format
  alias MediaCentarr.Library
  alias MediaCentarr.Library.{EntityShape, TypeResolver}
  alias MediaCentarr.Library.Progress, as: LibraryProgress
  alias MediaCentarr.Playback.Events
  alias MediaCentarr.Playback.Events.{EntityProgressUpdated, ExtraProgressUpdated}

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
        summary = MediaCentarr.Library.ProgressSummary.compute(entity, progress_records)
        resume_target = MediaCentarr.Playback.ResumeTarget.compute(entity, progress_records)

        Log.info(:playback, "broadcast progress — #{Format.short_id(entity_id)}")

        Events.broadcast(%EntityProgressUpdated{
          entity_id: entity_id,
          summary: summary,
          resume_target: resume_target,
          changed_record: changed_record,
          last_activity_at: DateTime.utc_now()
        })

      :not_found ->
        :ok
    end
  end

  defp resolve_entity_with_progress(id) do
    case TypeResolver.resolve_container(id, preload: Library.full_preloads_by_type()) do
      {:ok, type, record} ->
        progress =
          record
          |> EntityShape.extract_progress(type)
          |> overlay_in_memory_progress()

        normalized = EntityShape.to_view_model(record, type)
        {:ok, normalized, progress}

      :not_found ->
        :not_found
    end
  end

  # Overlays the hot-path in-memory WatchProgress state on top of the DB
  # read for each record's `playable_item_id`. Closes the stale-read
  # window introduced by Library Schema v2 Phase 3 Task D, where
  # `LibraryProgress.record/3` writes to the in-memory ETS table and
  # the debounced flush to `library_watch_progress` lands seconds
  # later — without this overlay the broadcast payload reflects the
  # *previous* persisted position instead of the live one.
  #
  # `Library.Progress.get/1` returns the in-memory row when present
  # and falls back to the persisted row otherwise; the fallback path
  # is equivalent to the original DB-only read, so this is safe for
  # rows that have no active session.
  defp overlay_in_memory_progress(progress_records) do
    Enum.map(progress_records, fn record ->
      # `lookup_in_memory/1` is the ETS-only variant — `get/1` would
      # fall through to a `Repo.get_by` round-trip for cold rows,
      # turning this overlay into an N+1 against the row we already
      # loaded from disk.
      case record.playable_item_id && LibraryProgress.lookup_in_memory(record.playable_item_id) do
        nil ->
          record

        %{} = fresh ->
          %{
            record
            | position_seconds: fresh.position_seconds,
              duration_seconds: fresh.duration_seconds,
              completed: fresh.completed,
              last_watched_at: fresh.last_watched_at
          }
      end
    end)
  end

  @doc """
  Broadcasts an `:extra_progress_updated` message for a specific extra.

  Simpler than entity broadcast — no summary/resume recomputation needed.
  Loads the current ExtraProgress record and broadcasts it.
  """
  def broadcast_extra(entity_id, extra_id) do
    progress = MediaCentarr.Library.get_extra_progress_by_extra(extra_id)

    Log.info(:playback, "broadcast extra progress — #{Format.short_id(extra_id)}")

    Events.broadcast(%ExtraProgressUpdated{
      entity_id: entity_id,
      extra_id: extra_id,
      progress: progress
    })
  end
end
