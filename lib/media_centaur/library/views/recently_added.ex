defmodule MediaCentaur.Library.Views.RecentlyAdded do
  @moduledoc """
  ETS-backed projection of Recently Added rows (ADR-041).

  Mirrors the output of `MediaCentaur.Library.list_recently_added/1`
  into a named ETS table holding `RecentlyAddedItem` structs keyed by
  display rank. Reads bypass the GenServer entirely — see
  `MediaCentaur.Library.Views.recently_added/1`.

  ## Refresh triggers

  Subscribes to two source topics:

    * `library:updates` — entity creates/edits/deletes (coalesced
      upstream by `Library.BroadcastCoalescer`).
    * `library:availability` — drive-mount and drive-unmount events.
      The underlying query reads `library_watched_files` rows, whose
      Phase-3 FK to `library_file_presences` (cascade-delete) makes
      WatchedFile existence equivalent to "current presence on disk."

  ## Storage

    * `:library_view_recently_added` — `:ordered_set`, `:public`,
      `:read_concurrency, true`. Keyed by display rank (`0..n-1`).
    * Refreshes replace every row in a single `:ets.delete_all_objects`
      + `:ets.insert` pair. Concurrent readers see either the previous
      snapshot or the new one, never a partial state.
  """
  @behaviour MediaCentaur.Cache

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Availability
  alias MediaCentaur.Library.Views.RankedProjection
  alias MediaCentaur.Library.Views.RecentlyAddedItem
  alias MediaCentaur.Topics

  @table :library_view_recently_added
  @max_items 60

  @impl MediaCentaur.Cache
  def subscribe do
    Topics.subscribe(Topics.library_updates())
    Availability.subscribe()
    :ok
  end

  @impl MediaCentaur.Cache
  def relevant?({:entities_changed, _}), do: true
  def relevant?({:availability_changed, _, _}), do: true
  def relevant?(_), do: false

  @impl MediaCentaur.Cache
  def refresh_cache do
    items =
      [limit: @max_items]
      |> Library.list_recently_added()
      |> Enum.map(&to_view_model/1)

    RankedProjection.replace_rows(@table, :recently_added, items)
  end

  @doc """
  Read the projection. Falls back to the underlying DB query when the
  ETS table is absent — covers test mode (Cache.Worker not started)
  and the brief window between boot and first refresh.
  """
  @spec read(keyword()) :: [RecentlyAddedItem.t()]
  def read(opts \\ []) do
    limit = Keyword.get(opts, :limit, 16)
    RankedProjection.read(@table, limit, fn -> read_from_db(limit) end)
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
end
