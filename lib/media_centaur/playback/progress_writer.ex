defmodule MediaCentaur.Playback.ProgressWriter do
  @moduledoc """
  Progress persistence for a viewing: what a session saves about an entry
  and when the entry counts as complete.

  `judge/4` is pure: it reads the saved position (the tracker's saveable
  position, else what mpv reports), judges it against
  `Completion.reason/3` and adds the entry's item to the session's
  completed set. `persist/5` runs the Library write in a task under
  `MediaCentaur.TaskSupervisor` — the hot-path write lands in the
  `Library.Progress` in-memory table in microseconds, the debounced flush
  persists it — and broadcasts the changed record. `broadcast_end/2` is
  the summary refresh a session sends when it finalises.

  An unattributed entry (a file the library does not know) is observed
  and never written.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Progress, as: LibraryProgress
  alias MediaCentaur.Playback.{Completion, Entry, MpvProperties, ProgressBroadcaster, WatchingTracker}

  @doc """
  Judges the saved position against `Completion.reason/3`; a complete one
  adds `Entry.item/1` to `completed`. Returns the reason (nil while
  incomplete) with the set.
  """
  @spec judge(MapSet.t(Entry.item()), Entry.t(), MpvProperties.t(), WatchingTracker.t()) ::
          {String.t() | nil, MapSet.t(Entry.item())}
  def judge(completed, %Entry{} = entry, %MpvProperties{} = properties, tracker) do
    reason =
      Completion.reason(saveable_position(tracker, properties), properties.duration, properties.chapters)

    case {reason, Entry.item(entry)} do
      {nil, _item} -> {nil, completed}
      {reason, nil} -> {reason, completed}
      {reason, item} -> {reason, MapSet.put(completed, item)}
    end
  end

  @doc "Saves the entry's progress for `profile_id` in a task; `reason` (from `judge/4`) marks it complete."
  @spec persist(String.t(), Entry.t(), MpvProperties.t(), WatchingTracker.t(), String.t() | nil) :: :ok
  def persist(profile_id, %Entry{} = entry, %MpvProperties{} = properties, tracker, reason) do
    saveable = saveable_position(tracker, properties)

    case Entry.item(entry) do
      {:extra, _id} -> persist_extra(profile_id, entry, saveable, properties.duration, reason)
      nil -> :ok
      _attributed -> persist_entity(profile_id, entry, saveable, properties.duration, reason)
    end
  end

  @doc "The end-of-playback summary refresh for the entry's entity, in a task."
  @spec broadcast_end(String.t(), Entry.t()) :: :ok
  def broadcast_end(profile_id, %Entry{entity_id: entity_id} = entry) do
    case Entry.item(entry) do
      {:extra, extra_id} ->
        start_task(fn -> ProgressBroadcaster.broadcast_extra(profile_id, entity_id, extra_id) end)

      # An unattributed file: nothing was tracked.
      nil ->
        :ok

      _attributed ->
        # Explicit nil: the per-tick broadcast in `persist/5` already
        # carried the changed playable_item_id, so there is no single
        # record to report here.
        start_task(fn -> ProgressBroadcaster.broadcast(profile_id, entity_id, nil) end)
    end
  end

  defp saveable_position(tracker, properties), do: tracker.saveable_position || properties.position

  defp persist_extra(profile_id, entry, saveable, duration, reason) do
    %Entry{entity_id: entity_id, extra_id: extra_id} = entry

    params = %{
      profile_id: profile_id,
      extra_id: extra_id,
      entity_id: entity_id,
      position_seconds: saveable,
      duration_seconds: duration
    }

    start_task(fn ->
      case Library.ProgressRecords.find_or_create_for_extra(params) do
        {:ok, record} ->
          Log.info(
            :playback,
            "saved extra progress — #{Format.format_seconds(saveable)} of #{Format.format_seconds(duration)}"
          )

          maybe_mark_extra_completed(record, reason)
          ProgressBroadcaster.broadcast_extra(profile_id, entity_id, extra_id)

        {:error, reason} ->
          Log.warning(:playback, "failed to save extra progress — #{inspect(reason)}")
      end
    end)
  end

  defp persist_entity(profile_id, entry, saveable, duration, reason) do
    entity_id = entry.entity_id

    start_task(fn ->
      case resolve_or_create_playable_item_id(entry) do
        {:ok, playable_item_id} ->
          # Hot-path write: lands in the Library.Progress in-memory
          # table in microseconds; the debounced flush persists to
          # `library_watch_progress` on the next interval (default 5s)
          # or synchronously on clean shutdown.
          :ok = LibraryProgress.record(profile_id, playable_item_id, saveable, duration)

          Log.info(
            :playback,
            "saved progress — #{Format.format_seconds(saveable)} of #{Format.format_seconds(duration)}"
          )

          maybe_mark_completed(profile_id, playable_item_id, reason)
          # The rich `%EntityProgressUpdated{}` event carries the changed
          # record, so the detail modal's in-memory merge flips a
          # per-episode badge live rather than on a full remount.
          ProgressBroadcaster.broadcast(profile_id, entity_id, playable_item_id)

        {:error, reason} ->
          Log.warning(:playback, "failed to save progress — #{inspect(reason)}")
      end
    end)
  end

  defp start_task(fun) do
    {:ok, _pid} = Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fun)
    :ok
  end

  # Resolves the canonical PlayableItem for the entry's playable without
  # writing any WatchProgress row — that's the Progress worker's job.
  defp resolve_or_create_playable_item_id(%Entry{movie_id: movie_id}) when not is_nil(movie_id) do
    position =
      case Library.Containers.fetch(:movie, movie_id) do
        {:ok, %{position: pos}} when is_integer(pos) -> pos
        _ -> 1
      end

    case Library.PlayableItems.find_or_create(:movie, movie_id, position) do
      {:ok, %{id: id}} -> {:ok, id}
      other -> other
    end
  end

  defp resolve_or_create_playable_item_id(%Entry{episode_id: episode_id}) when not is_nil(episode_id) do
    position =
      case Library.Episodes.fetch(episode_id) do
        {:ok, %{episode_number: n}} when is_integer(n) -> n
        _ -> 1
      end

    case Library.PlayableItems.find_or_create(:episode, episode_id, position) do
      {:ok, %{id: id}} -> {:ok, id}
      other -> other
    end
  end

  defp resolve_or_create_playable_item_id(%Entry{video_object_id: vo_id}) when not is_nil(vo_id) do
    case Library.PlayableItems.find_or_create(:video_object, vo_id, 1) do
      {:ok, %{id: id}} -> {:ok, id}
      other -> other
    end
  end

  defp maybe_mark_completed(_profile_id, _playable_item_id, nil), do: :ok

  defp maybe_mark_completed(profile_id, playable_item_id, reason) do
    case LibraryProgress.get(profile_id, playable_item_id) do
      %{completed: true} ->
        :ok

      _ ->
        Log.info(:playback, "marked completed — #{reason}")
        :ok = LibraryProgress.complete(profile_id, playable_item_id)
    end
  end

  defp maybe_mark_extra_completed(_record, nil), do: :ok
  defp maybe_mark_extra_completed(%{completed: true}, _reason), do: :ok

  defp maybe_mark_extra_completed(record, reason) do
    Log.info(:playback, "extra marked completed — #{reason}")

    case Library.ProgressRecords.mark_completed(record) do
      {:ok, _} -> :ok
      {:error, error} -> Log.warning(:playback, "failed to mark extra completed — #{inspect(error)}")
    end
  end
end
