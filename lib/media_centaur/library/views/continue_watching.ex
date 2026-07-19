defmodule MediaCentaur.Library.Views.ContinueWatching do
  @moduledoc """
  ETS-backed projection of Continue Watching rows (ADR-041).

  The projection mirrors the output of `MediaCentaur.Library.list_in_progress/1`
  into a named ETS table holding `ContinueWatchingItem` structs keyed
  by display rank. Reads bypass the GenServer entirely — see
  `MediaCentaur.Library.Views.continue_watching/1`.

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
      The underlying `Library.list_in_progress/1` joins
      `library_watched_files`, whose FK to `library_file_presences`
      (cascade-delete) makes file presence equivalent to "currently
      on disk." When a drive disappears, in-progress rows for its
      titles must vanish from the row; when it returns, they reappear.

  Other `playback:events` (`:playback_state_changed`,
  `:extra_progress_updated`) do not affect Continue Watching's
  underlying data; subscribers that care about playback-driven UI
  ordering (e.g. pinning the now-playing item to the front of the row)
  consume `playback:events` directly.

  ## Storage

    * `:library_view_continue_watching` — `:ordered_set`, `:public`,
      `:read_concurrency, true`. Keyed by display rank (`0..n-1`).
      Owned by the Cache.Worker that drives this projection.
    * Refreshes replace every row in a single `:ets.delete_all_objects`
      + `:ets.insert` pair. Concurrent readers see either the previous
      snapshot or the new one, never a partial state.

  ## Refresh cap

  The projection over-fetches up to `@max_items` rows so callers with
  larger `:limit` values still see a complete list. Larger libraries
  with many in-progress entries truncate at this bound; a future
  refinement can lift the cap if real usage demands it.
  """
  @behaviour MediaCentaur.Cache

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Availability
  alias MediaCentaur.Library.Views.ContinueWatchingItem
  alias MediaCentaur.Library.Views.RankedProjection
  alias MediaCentaur.Topics

  @table :library_view_continue_watching
  @max_items 100

  @impl MediaCentaur.Cache
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.library_updates())
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.watch_history_events())
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.playback_events())
    Availability.subscribe()
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
    items =
      [limit: @max_items]
      |> Library.list_in_progress()
      |> Enum.map(&to_view_model/1)

    RankedProjection.replace_rows(@table, :continue_watching, items)
  end

  @doc """
  Read the projection. Falls back to the underlying DB query when the
  ETS table is absent — covers test mode (Cache.Worker not started)
  and the brief window between boot and first refresh.
  """
  @spec read(keyword()) :: [ContinueWatchingItem.t()]
  def read(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)
    RankedProjection.read(@table, limit, fn -> read_from_db(limit) end)
  end

  defp read_from_db(limit) do
    [limit: limit]
    |> Library.list_in_progress()
    |> Enum.map(&to_view_model/1)
  end

  defp to_view_model(row) do
    %ContinueWatchingItem{
      entity_id: row.entity_id,
      entity_name: row.entity_name,
      last_episode_label: Map.get(row, :last_episode_label),
      progress_pct: Map.get(row, :progress_pct),
      backdrop_url: Map.get(row, :backdrop_url),
      logo_url: Map.get(row, :logo_url),
      last_watched_at: Map.get(row, :last_watched_at)
    }
  end
end
