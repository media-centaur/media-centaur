defmodule MediaCentaur.Playback.ProgressWriter do
  @moduledoc """
  Progress persistence for a viewing: what a session saves about an entry
  and when the entry counts as complete.

  `decide/4` is pure: it says what a persist does — nothing, a tick or a
  finish — and returns the session's completed set. `judge/4` reads the
  saved position (the tracker's saveable position, else what mpv
  reports) and judges it against `Completion.reason/4`; a finish adds the
  entry's item to the set. That set is the only guard against a repeated
  finish: `completed?/2` reads it, and a session persists nothing more
  for an item it has finished.

  `persist/6` makes the writes, and one session's writes are ordered
  because of where each runs. The tick is written in the calling process,
  the session: for a playable item an insert into the `Library.Progress`
  in-memory table (the debounced flush persists it), for an extra its
  row. The finish runs after it in a task under
  `MediaCentaur.TaskSupervisor`, with the broadcast of the changed
  record. A session issues no tick for an item after its finish, so a
  tick can never be applied after the finish it preceded. A finish that
  fails is sent back to the session as `{:finish_failed, item}`;
  `unfinished/2` takes the item out of the set, and the next persist
  judges it again. `broadcast_end/2` is the summary refresh a session
  sends when it finalises.

  An unattributed entry (a file the library does not know) is observed
  and never written.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Progress, as: LibraryProgress
  alias MediaCentaur.Profiles.Actor
  alias MediaCentaur.Playback.{Completion, Entry, MpvProperties, ProgressBroadcaster, WatchingTracker}

  @doc """
  Judges the saved position against `Completion.reason/4` for the entry's
  kind of playable; a complete one adds `Entry.item/1` to `completed`. Returns the reason (nil while
  incomplete) with the set.
  """
  @spec judge(MapSet.t(Entry.item()), Entry.t(), MpvProperties.t(), WatchingTracker.t()) ::
          {String.t() | nil, MapSet.t(Entry.item())}
  def judge(completed, %Entry{} = entry, %MpvProperties{} = properties, tracker) do
    item = Entry.item(entry)

    reason =
      Completion.reason(
        saveable_position(tracker, properties),
        properties.duration,
        properties.chapters,
        item && elem(item, 0)
      )

    case {reason, item} do
      {nil, _item} -> {nil, completed}
      {reason, nil} -> {reason, completed}
      {reason, item} -> {reason, MapSet.put(completed, item)}
    end
  end

  @doc "Whether the session has already finished the entry's item — after that it persists nothing more for it."
  @spec completed?(MapSet.t(Entry.item()), Entry.t()) :: boolean()
  def completed?(completed, %Entry{} = entry) do
    case Entry.item(entry) do
      nil -> false
      item -> MapSet.member?(completed, item)
    end
  end

  @typedoc "What one persist does: nothing, a position tick, or a tick and the finish (with `judge/4`'s reason)."
  @type action :: :nothing | :tick | {:finish, String.t()}

  @doc """
  What a persist of the entry does, with the session's completed set
  after it. Nothing for an unattributed entry and for an item the session
  has finished: ticks through the credits are not a new viewing, and a
  finish happens once per viewing.
  """
  @spec decide(MapSet.t(Entry.item()), Entry.t(), MpvProperties.t(), WatchingTracker.t()) ::
          {action(), MapSet.t(Entry.item())}
  def decide(completed, %Entry{} = entry, %MpvProperties{} = properties, tracker) do
    if completed?(completed, entry) or not Entry.attributed?(entry) do
      {:nothing, completed}
    else
      case judge(completed, entry, properties, tracker) do
        {nil, completed} -> {:tick, completed}
        {reason, completed} -> {{:finish, reason}, completed}
      end
    end
  end

  @doc "The completed set after the finish of `item` failed (`{:finish_failed, item}`): the next persist judges it again."
  @spec unfinished(MapSet.t(Entry.item()), Entry.item()) :: MapSet.t(Entry.item())
  def unfinished(completed, item), do: MapSet.delete(completed, item)

  @doc """
  Carries out `action` (from `decide/4`) for the entry, called by the
  session process. The tick is written before this returns; a finish
  follows it in a task, which sends `{:finish_failed, item}` to the
  caller if the item was not finished.

  `playable_item_id` is the entry's playable item as the session holds
  it, `nil` until the first write resolves it; the return value is what
  the session holds from then on (always `nil` for an extra, which is
  keyed by its own id).
  """
  @spec persist(
          action(),
          String.t(),
          Entry.t(),
          String.t() | nil,
          MpvProperties.t(),
          WatchingTracker.t()
        ) ::
          String.t() | nil
  def persist(:nothing, _profile_id, _entry, playable_item_id, _properties, _tracker),
    do: playable_item_id

  def persist(
        action,
        profile_id,
        %Entry{} = entry,
        playable_item_id,
        %MpvProperties{} = properties,
        tracker
      ) do
    saveable = saveable_position(tracker, properties)

    case Entry.item(entry) do
      {:extra, _id} -> persist_extra(action, profile_id, entry, saveable, properties.duration)
      _item -> persist_item(action, profile_id, entry, playable_item_id, saveable, properties.duration)
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

  defp persist_extra(action, profile_id, entry, saveable, duration) do
    %Entry{entity_id: entity_id, extra_id: extra_id} = entry

    params = %{
      profile_id: profile_id,
      extra_id: extra_id,
      entity_id: entity_id,
      position_seconds: saveable,
      duration_seconds: duration
    }

    case Library.ProgressRecords.find_or_create_for_extra(params) do
      {:ok, record} ->
        Log.info(
          :playback,
          "saved extra progress — #{Format.format_seconds(saveable)} of #{Format.format_seconds(duration)}"
        )

        session = self()

        start_task(fn ->
          finish_extra(action, record, session, Entry.item(entry))
          ProgressBroadcaster.broadcast_extra(profile_id, entity_id, extra_id)
        end)

      {:error, reason} ->
        Log.warning(:playback, "failed to save extra progress — #{inspect(reason)}")
        report_unfinished(action, self(), Entry.item(entry))
    end

    nil
  end

  defp persist_item(action, profile_id, entry, playable_item_id, saveable, duration) do
    case resolve_playable_item_id(entry, playable_item_id) do
      {:ok, playable_item_id} ->
        # Lands in the Library.Progress in-memory table in microseconds;
        # the debounced flush persists to `library_watch_progress` on the
        # next interval (default 5s) or synchronously on clean shutdown.
        :ok = LibraryProgress.record(profile_id, playable_item_id, saveable, duration)

        Log.info(
          :playback,
          "saved progress — #{Format.format_seconds(saveable)} of #{Format.format_seconds(duration)}"
        )

        session = self()

        start_task(fn ->
          finish_item(action, profile_id, playable_item_id, session, Entry.item(entry))
          # The rich `%EntityProgressUpdated{}` event carries the changed
          # record, so the detail modal's in-memory merge flips a
          # per-episode badge live rather than on a full remount.
          ProgressBroadcaster.broadcast(profile_id, entry.entity_id, playable_item_id)
        end)

        playable_item_id

      {:error, reason} ->
        Log.warning(:playback, "failed to save progress — #{inspect(reason)}")
        report_unfinished(action, self(), Entry.item(entry))
        nil
    end
  end

  defp start_task(fun) do
    {:ok, _pid} = Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fun)
    :ok
  end

  # The session resolves an entry's playable item once and hands it back
  # at every later persist.
  defp resolve_playable_item_id(_entry, playable_item_id) when is_binary(playable_item_id),
    do: {:ok, playable_item_id}

  defp resolve_playable_item_id(entry, nil), do: resolve_or_create_playable_item_id(entry)

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

  # The session judged the finish and holds the item in its completed
  # set, so this runs once per viewing — unless it fails, and the session
  # is told to judge the item again.
  defp finish_item(:tick, _profile_id, _playable_item_id, _session, _item), do: :ok

  defp finish_item({:finish, reason} = action, profile_id, playable_item_id, session, item) do
    case LibraryProgress.complete(Actor.new(profile_id), playable_item_id) do
      :ok ->
        Log.info(:playback, "marked completed — #{reason}")

      {:error, error} ->
        Log.warning(:playback, "failed to mark completed — #{inspect(error)}")
        report_unfinished(action, session, item)
    end
  end

  defp finish_extra(:tick, _record, _session, _item), do: :ok

  defp finish_extra({:finish, reason} = action, record, session, item) do
    case Library.ProgressRecords.finish_extra(record, record.duration_seconds) do
      {:ok, _finished} ->
        Log.info(:playback, "extra marked completed — #{reason}")

      {:error, error} ->
        Log.warning(:playback, "failed to mark extra completed — #{inspect(error)}")
        report_unfinished(action, session, item)
    end
  end

  defp report_unfinished(:tick, _session, _item), do: :ok

  defp report_unfinished({:finish, _reason}, session, item) do
    send(session, {:finish_failed, item})
    :ok
  end
end
