defmodule MediaCentarr.Library.Views.RecentlyAdded do
  @moduledoc """
  ETS-backed projection of Recently Added rows (ADR-041).

  Mirrors the output of `MediaCentarr.Library.list_recently_added/1`
  into a named ETS table holding `RecentlyAddedItem` structs keyed by
  display rank. Reads bypass the GenServer entirely — see
  `MediaCentarr.Library.Views.recently_added/1`.

  ## Refresh triggers

  Subscribes to two source topics:

    * `library:updates` — entity creates/edits/deletes (coalesced
      upstream by `Library.BroadcastCoalescer`).
    * `library:availability` — drive-mount and drive-unmount events.
      The underlying query filters on `library_watched_files` joined
      to `watcher_files.state == "present"`, so a presence flip
      changes the result set.

  ## Storage

    * `:library_view_recently_added` — `:ordered_set`, `:public`,
      `:read_concurrency, true`. Keyed by display rank (`0..n-1`).
    * Refreshes replace every row in a single `:ets.delete_all_objects`
      + `:ets.insert` pair. Concurrent readers see either the previous
      snapshot or the new one, never a partial state.
  """
  @behaviour MediaCentarr.Cache

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Availability
  alias MediaCentarr.Library.Views.RecentlyAddedItem
  alias MediaCentarr.Topics

  @table :library_view_recently_added
  @max_items 60

  @impl MediaCentarr.Cache
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_updates())
    Availability.subscribe()
    :ok
  end

  @impl MediaCentarr.Cache
  def relevant?({:entities_changed, _}), do: true
  def relevant?({:availability_changed, _, _}), do: true
  def relevant?(_), do: false

  @impl MediaCentarr.Cache
  def refresh_cache do
    ensure_table()

    items =
      [limit: @max_items]
      |> Library.list_recently_added()
      |> Enum.map(&to_view_model/1)

    rows = Enum.with_index(items, fn item, rank -> {rank, item} end)

    :ets.delete_all_objects(@table)
    :ets.insert(@table, rows)

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.library_views(),
      {:library_view_updated, :recently_added}
    )

    :ok
  end

  @doc """
  Read the projection. Falls back to the underlying DB query when the
  ETS table is absent — covers test mode (Cache.Worker not started)
  and the brief window between boot and first refresh.
  """
  @spec read(keyword()) :: [RecentlyAddedItem.t()]
  def read(opts \\ []) do
    limit = Keyword.get(opts, :limit, 16)

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
    |> Library.list_recently_added()
    |> Enum.map(&to_view_model/1)
  end

  defp to_view_model(row) do
    %RecentlyAddedItem{
      id: row.id,
      name: row.name,
      year: Map.get(row, :year),
      poster_url: Map.get(row, :poster_url)
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
