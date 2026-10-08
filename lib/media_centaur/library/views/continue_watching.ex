defmodule MediaCentaur.Library.Views.ContinueWatching do
  @moduledoc """
  ETS-backed projection of Continue Watching rows (ADR-041).

  Profile-keyed (ADR-078): the `:set` holds `{profile_id, items}` for
  every profile with a progress row, rebuilt whole on every relevant
  event — a household is a handful of profiles. The derived message is
  unchanged; a page re-reads for its own profile. `items` is the output
  of `MediaCentaur.Library.list_in_progress/2` as `ContinueWatchingItem`
  structs in display order. Reads bypass the GenServer entirely — see
  `MediaCentaur.Library.Views.continue_watching/2`.

  ## Refresh triggers

  Subscribes to four source topics:

    * `library:updates` — entity creates/edits/deletes
      (already coalesced upstream by `Library.BroadcastCoalescer`).
    * `watch_history:events` — completion events that promote/remove
      entries. Two completion signals arrive here: the async,
      best-effort `{:watch_event_created, _}` (emitted by the Recorder
      after resolving a title) and the synchronous, deterministic
      `{:watch_completed, playable_item_id}` (emitted by
      `Library.Progress.Worker` immediately after it persists
      `completed: true`). Both trigger a rebuild; the deterministic one
      guarantees a finished item drops from the row live even if the
      Recorder's title lookup lags or fails, instead of lingering until
      a manual page reload.
    * `playback:events` — `:entity_progress_updated` keeps the
      progress bar live during active playback. Rebuild cost is
      sub-millisecond per event (one indexed query + struct mapping
      for top-N rows) and the event rate is a few per second per
      active session — single-user, single-session means at most one
      rebuild per few seconds during playback. Cheap; preserves the
      existing UX where the bar ticks forward without page reload.
    * `library:availability` — drive-mount and drive-unmount events.
      The underlying `Library.list_in_progress/2` joins
      `library_watched_files`, whose FK to `library_file_presences`
      (cascade-delete) makes file presence equivalent to "currently
      on disk." When a drive disappears, in-progress rows for its
      titles must vanish from the row; when it returns, they reappear.
      The same event re-resolves each row's `available?` and artwork
      through `Views.ItemAvailability`.

  Other `playback:events` (`:playback_state_changed`,
  `:extra_progress_updated`) do not affect Continue Watching's
  underlying data; subscribers that care about playback-driven UI
  ordering (e.g. pinning the now-playing item to the front of the row)
  consume `playback:events` directly.

  ## Storage

    * `:library_view_continue_watching` — `:set`, `:public`,
      `:read_concurrency, true`. One `{profile_id, items}` row per
      profile. Owned by the Cache.Worker that drives this projection.
    * Refreshes replace every row in a single `:ets.delete_all_objects`
      + `:ets.insert` pair. Concurrent readers see either the previous
      snapshot or the new one, never a partial state.

  ## Refresh cap

  The projection over-fetches up to `@max_items` rows per profile so
  callers with larger `:limit` values still see a complete list. Larger libraries
  with many in-progress entries truncate at this bound; a future
  refinement can lift the cap if real usage demands it.
  """
  @behaviour MediaCentaur.Cache

  alias MediaCentaur.Library
  alias MediaCentaur.Library.MediaFileAvailability
  alias MediaCentaur.Library.ProgressRecords
  alias MediaCentaur.Library.Views.ContinueWatchingItem
  alias MediaCentaur.Library.Views.ItemAvailability
  alias MediaCentaur.Topics

  @table :library_view_continue_watching
  @max_items 100
  @ets_opts [:set, :public, :named_table, read_concurrency: true]

  @impl MediaCentaur.Cache
  def subscribe do
    Topics.subscribe(Topics.library_updates())
    Topics.subscribe(Topics.watch_history_events())
    Topics.subscribe(Topics.playback_events())
    MediaFileAvailability.subscribe()
    :ok
  end

  @impl MediaCentaur.Cache
  def relevant?({:entities_changed, _}), do: true
  def relevant?({:watch_event_created, _}), do: true
  def relevant?({:entity_progress_updated, _}), do: true
  def relevant?({:watch_completed, _playable_item_id}), do: true
  def relevant?({:availability_changed, _dir, _state}), do: true
  def relevant?(_), do: false

  @impl MediaCentaur.Cache
  def refresh_cache do
    ensure_table()

    rows =
      for profile_id <- ProgressRecords.profile_ids_with_progress(),
          do: {profile_id, build(profile_id, @max_items)}

    :ets.delete_all_objects(@table)
    :ets.insert(@table, rows)
    Topics.publish(Topics.library_views(), {:library_view_updated, :continue_watching})
    :ok
  end

  @doc """
  Read one profile's shelf. Falls back to the underlying query when the
  ETS table is absent — test mode (no `Cache.Worker`) and the window
  between boot and first refresh. A profile with no rows reads `[]`.
  """
  @spec read(Ecto.UUID.t(), keyword()) :: [ContinueWatchingItem.t()]
  def read(profile_id, opts \\ []) when is_binary(profile_id) do
    limit = Keyword.get(opts, :limit, 12)

    case :ets.whereis(@table) do
      :undefined ->
        build(profile_id, limit)

      _ref ->
        case :ets.lookup(@table, profile_id) do
          [{^profile_id, items}] -> Enum.take(items, limit)
          [] -> []
        end
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, @ets_opts)
      _ref -> :ok
    end

    :ok
  end

  defp build(profile_id, limit) do
    profile_id
    |> Library.list_in_progress(limit: limit)
    |> Enum.map(&to_view_model/1)
    |> ItemAvailability.resolve(id: :entity_id, artwork: [:backdrop_url, :logo_url])
  end

  defp to_view_model(row) do
    %ContinueWatchingItem{
      entity_id: row.entity_id,
      entity_name: row.entity_name,
      progress_pct: Map.get(row, :progress_pct),
      backdrop_url: Map.get(row, :backdrop_url),
      logo_url: Map.get(row, :logo_url),
      last_watched_at: Map.get(row, :last_watched_at)
    }
  end
end
