defmodule MediaCentarr.Library.Views.ContinueWatching do
  @moduledoc """
  ETS-backed projection of Continue Watching rows (ADR-041).

  The projection mirrors the output of `MediaCentarr.Library.list_in_progress/1`
  into a named ETS table holding `ContinueWatchingItem` structs keyed
  by display rank. Reads bypass the GenServer entirely — see
  `MediaCentarr.Library.Views.continue_watching/1`.

  ## Refresh triggers

  Subscribes to three source topics:

    * `library:updates` — entity creates/edits/deletes
      (already coalesced upstream by `Library.BroadcastCoalescer`).
    * `watch_history:events` — completion events that promote/remove
      entries.
    * `playback:events` — `:entity_progress_updated` keeps the
      progress bar live during active playback. Rebuild cost is
      sub-millisecond per event (one indexed query + struct mapping
      for top-N rows) and the event rate is a few per second per
      active session — single-user, single-session means at most one
      rebuild per few seconds during playback. Cheap; preserves the
      existing UX where the bar ticks forward without page reload.

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
  @behaviour MediaCentarr.Cache

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Views.ContinueWatchingItem
  alias MediaCentarr.Topics

  @table :library_view_continue_watching
  @max_items 100

  @impl MediaCentarr.Cache
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_updates())
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.watch_history_events())
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.playback_events())
    :ok
  end

  @impl MediaCentarr.Cache
  def relevant?({:entities_changed, _}), do: true
  def relevant?({:watch_event_created, _}), do: true
  def relevant?({:entity_progress_updated, _}), do: true
  def relevant?(_), do: false

  @impl MediaCentarr.Cache
  def refresh_cache do
    ensure_table()

    items =
      [limit: @max_items]
      |> Library.list_in_progress()
      |> Enum.map(&to_view_model/1)

    rows = Enum.with_index(items, fn item, rank -> {rank, item} end)

    :ets.delete_all_objects(@table)
    :ets.insert(@table, rows)

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.library_views(),
      {:library_view_updated, :continue_watching}
    )

    :ok
  end

  @doc """
  Read the projection. Falls back to the underlying DB query when the
  ETS table is absent — covers test mode (Cache.Worker not started)
  and the brief window between boot and first refresh.
  """
  @spec read(keyword()) :: [ContinueWatchingItem.t()]
  def read(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)

    case :ets.whereis(@table) do
      :undefined -> read_from_db(limit)
      _ref -> read_from_ets(limit)
    end
  end

  defp read_from_ets(limit) do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {rank, _item} -> rank end)
    |> Enum.take(limit)
    |> Enum.map(fn {_rank, item} -> item end)
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

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:ordered_set, :public, :named_table, read_concurrency: true])

      _ref ->
        :ok
    end
  end
end
