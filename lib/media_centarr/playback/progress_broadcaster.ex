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
  alias MediaCentarr.Library.Progress, as: LibraryProgress
  alias MediaCentarr.Library.Views, as: LibraryViews
  alias MediaCentarr.Library.Views.DetailItem
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
          changed_record: enrich_changed_record(changed_record, progress_records),
          last_activity_at: DateTime.utc_now()
        })

      :not_found ->
        :ok
    end
  end

  # Substitute the caller's raw `changed_record` with the matching record
  # from the freshly loaded `progress_records` list. The DB-loaded version
  # carries the synthesised `:playable_item` (via
  # `EntityShape.extract_progress/2`) that subscribers need to key by
  # container id (`EpisodeList.progress_container_id/1`). The caller's
  # record — what `Library.fetch_watch_progress_by_fk/2` and
  # `mark_watch_completed!/1` return — has `:playable_item` as
  # `%Ecto.Association.NotLoaded{}`, which would silently drop the
  # record out of the modal's in-memory merge.
  defp enrich_changed_record(nil, _records), do: nil

  defp enrich_changed_record(changed_record, records) do
    case Enum.find(records, &(&1.id == changed_record.id)) do
      nil -> changed_record
      enriched -> enriched
    end
  end

  # Resolves the entity via the Library Detail ETS projection (ADR-041)
  # instead of `TypeResolver.resolve_container` + a full preload tree.
  # Every progress tick during playback hits this path; the previous
  # implementation issued up to 4 sequential `Repo.get` probes followed
  # by a deep `Repo.preload` (`seasons: [:extras, episodes: [:images,
  # :watch_progress, playable_items: :watched_files]]`). The projection
  # already holds the same shape consumers need; reads are microsecond
  # ETS lookups (with a DB fallback for test mode / pre-boot window —
  # `Views.detail_by_container/2` handles both).
  #
  # The function still probes 4 container types since the broadcaster
  # only receives `entity_id`. Future work: thread the known type from
  # MpvSession so the probe loop drops to a single direct lookup.
  defp resolve_entity_with_progress(id) do
    cond do
      result = load_via_detail(:tv_series, id) -> result
      result = load_via_detail(:movie_series, id) -> result
      result = load_via_detail(:movie, id) -> result
      result = load_via_detail(:video_object, id) -> result
      true -> :not_found
    end
  end

  defp load_via_detail(type, id) do
    case LibraryViews.detail_by_container(type, id) do
      %DetailItem{} = item ->
        entity = DetailItem.to_entity_map(item)

        progress_records =
          type
          |> Library.list_progress_records_for_container(id)
          |> overlay_in_memory_progress()

        {:ok, entity, progress_records}

      nil ->
        nil
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
