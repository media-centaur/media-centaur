defmodule MediaCentaur.Playback.ProgressBroadcaster do
  @moduledoc """
  Broadcasts entity progress updates to the playback PubSub topic.

  Loads the entity and the profile's progress through it
  (`MediaCentaur.Library.ProgressRecords.title_progress/2`) and broadcasts
  both to `"playback:events"`. Used by the playback session (after
  recording progress) and the detail page (after a watched control).
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Views, as: LibraryViews
  alias MediaCentaur.Library.Views.DetailItem
  alias MediaCentaur.Playback.Events
  alias MediaCentaur.Playback.Events.{EntityProgressUpdated, ExtraProgressUpdated}

  @doc """
  Loads `profile_id`'s progress on the entity and broadcasts an
  `:entity_progress_updated` message naming that profile.

  `changed` identifies the `WatchProgress` whose change triggered this
  broadcast, in either of two forms:

    * a `%WatchProgress{}` struct — the modal toggle path
      (`EntityModal.toggle_watch_progress/3`), which already holds the
      record;
    * a `playable_item_id` binary — the playback path
      (`MediaCentaur.Playback.MpvSession`), which knows the item that
      ticked but not a struct.

  Both resolve, by `playable_item_id`, to the freshly-loaded record from
  `progress_records` — the version that carries the synthesised
  `:playable_item` subscribers need to key by container id
  (`ProgressRecords.progress_container_id/1`). Subscribers (LiveViews) use
  the result to keep their in-memory per-entity `progress_records` list
  in sync with the title progress; without it the modal's
  in-memory merge no-ops and a per-episode badge never flips live.

  The argument is **required** — there is deliberately no default. A
  silent `nil` default is what let the playback path ship a payload with
  `changed_record: nil`, defeating the modal's in-memory merge. Making it
  required forces every caller to consciously state what changed; pass
  `nil` explicitly only when there genuinely is no single record (e.g. a
  bulk recomputation or an end-of-playback refresh).
  """
  @spec broadcast(Ecto.UUID.t(), Ecto.UUID.t(), map() | String.t() | nil) :: :ok | {:error, term()}
  def broadcast(profile_id, entity_id, changed) do
    case resolve_entity(entity_id) do
      {:ok, entity} ->
        %{title_progress: title_progress, records: progress_records} =
          Library.ProgressRecords.title_progress(profile_id, entity)

        Log.info(:playback, "broadcast progress — #{Format.short_id(entity_id)}")

        Events.broadcast(%EntityProgressUpdated{
          entity_id: entity_id,
          profile_id: profile_id,
          title_progress: title_progress,
          changed_record: select_changed_record(progress_records, changed),
          last_activity_at: DateTime.utc_now()
        })

      :not_found ->
        :ok
    end
  end

  # Resolve the caller's `changed` hint to the matching record from the
  # freshly loaded `progress_records` list (each at its live offset, so a
  # tick is not read from the row its debounced flush has yet to write) by
  # `playable_item_id` — unique
  # within one profile's rows, and the list is one profile's
  # (`(profile_id, playable_item_id)`, ADR-078). The list version carries
  # the synthesised `:playable_item`
  # subscribers key by container id; the caller's own record — whether a
  # raw `ProgressRecords.fetch_for_container/3` result with
  # `:playable_item` as `%Ecto.Association.NotLoaded{}`, or an in-memory
  # row from `Library.Progress.get/2` with `id: nil` — is unsuitable to
  # pass through directly, which is why we substitute rather than echo.
  # Returns `nil` when no single record is implicated, or when the
  # implicated row isn't in the list yet (e.g. a brand-new item whose
  # first persisted row hasn't landed).
  defp select_changed_record(_records, nil), do: nil

  defp select_changed_record(records, %{playable_item_id: playable_item_id}),
    do: find_by_playable_item_id(records, playable_item_id)

  defp select_changed_record(records, playable_item_id) when is_binary(playable_item_id),
    do: find_by_playable_item_id(records, playable_item_id)

  defp find_by_playable_item_id(records, playable_item_id),
    do: Enum.find(records, &(&1.playable_item_id == playable_item_id))

  # Resolves the entity via the Library Detail ETS projection (ADR-041)
  # instead of `TypeResolver.resolve_container` + a full preload tree.
  # Every progress tick during playback hits this path; the previous
  # implementation issued up to 4 sequential `Repo.get` probes followed
  # by a deep `Repo.preload` (`seasons: [:extras, episodes: [:images,
  # playable_items: :watched_files]]`). The projection
  # already holds the same shape consumers need; reads are microsecond
  # ETS lookups (with a DB fallback for test mode / pre-boot window —
  # `Views.detail_by_container/2` handles both).
  #
  # The function still probes 4 container types since the broadcaster
  # only receives `entity_id`. Future work: thread the known type from
  # MpvSession so the probe loop drops to a single direct lookup.
  defp resolve_entity(id) do
    Enum.find_value([:tv_series, :movie_series, :movie, :video_object], :not_found, fn type ->
      case LibraryViews.detail_by_container(type, id) do
        %DetailItem{} = item -> {:ok, DetailItem.to_entity_view(item)}
        nil -> nil
      end
    end)
  end

  @doc """
  Broadcasts an `:extra_progress_updated` message for a specific extra,
  naming `profile_id`, the profile the change was recorded under.

  Simpler than entity broadcast — an extra is part of no title progress.
  Loads the current ExtraProgress record and broadcasts it.
  """
  @spec broadcast_extra(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
  def broadcast_extra(profile_id, entity_id, extra_id) do
    progress =
      case MediaCentaur.Library.ProgressRecords.fetch_for_extra(profile_id, extra_id) do
        {:ok, record} -> record
        {:error, :not_found} -> nil
      end

    Log.info(:playback, "broadcast extra progress — #{Format.short_id(extra_id)}")

    Events.broadcast(%ExtraProgressUpdated{
      entity_id: entity_id,
      profile_id: profile_id,
      extra_id: extra_id,
      progress: progress
    })
  end
end
