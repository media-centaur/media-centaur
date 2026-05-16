defmodule MediaCentarr.Library.Views.Browse do
  @moduledoc """
  ETS-backed projection of the library browse grid (ADR-041,
  Library Schema v2 Phase 3 Task A).

  Mirrors the output of `MediaCentarr.Library.Browser.fetch_all_typed_entries/0`
  into a named ETS table holding `BrowseItem` view-model structs keyed
  by display rank. Reads bypass the GenServer entirely — see
  `MediaCentarr.Library.Views.browse/1`.

  ## Refresh triggers

  Subscribes to two source topics:

    * `library:updates` — entity creates / edits / deletes
      (already coalesced upstream by `Library.BroadcastCoalescer`).
    * `library:availability` — drive-mount and drive-unmount events.
      The underlying query reads `library_watched_files` rows, whose
      Phase-3 FK to `library_file_presences` (cascade-delete) makes
      WatchedFile existence equivalent to "current presence on disk."

  ## Storage

    * `:library_view_browse` — `:ordered_set`, `:public`, `:named_table`,
      `:read_concurrency, true`. Keyed by display rank (`0..n-1`).
    * Refreshes replace every row in a single `:ets.delete_all_objects`
      + `:ets.insert` pair. Concurrent readers see either the previous
      snapshot or the new one, never a partial state.

  ## Refresh cap

  The projection holds at most `@max_items` rows. The current library
  browse renders the full catalog (no pagination), so the cap is a
  defensive ceiling — bumping it is a one-line change if real
  catalogues outgrow the limit.
  """
  @behaviour MediaCentarr.Cache

  alias MediaCentarr.Library.Availability
  alias MediaCentarr.Library.Browser
  alias MediaCentarr.Library.Views.BrowseItem
  alias MediaCentarr.Topics

  @table :library_view_browse
  @max_items 10_000

  @impl MediaCentarr.Cache
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_updates())
    Availability.subscribe()
    :ok
  end

  @impl MediaCentarr.Cache
  def relevant?({:entities_changed, _}), do: true
  def relevant?({:availability_changed, _dir, _state}), do: true
  def relevant?(_), do: false

  @impl MediaCentarr.Cache
  def refresh_cache do
    ensure_table()

    items =
      Browser.fetch_all_typed_entries()
      |> Enum.take(@max_items)
      |> Enum.map(&to_view_model/1)

    rows = Enum.with_index(items, fn item, rank -> {rank, %{item | rank: rank}} end)

    :ets.delete_all_objects(@table)
    :ets.insert(@table, rows)

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.library_views(),
      {:library_view_updated, :browse}
    )

    :ok
  end

  @doc """
  Read the projection. Falls back to the underlying DB query when the
  ETS table is absent — covers test mode (Cache.Worker not started)
  and the brief window between boot and first refresh.

  Options:
    * `:kind` — filter by `:movie | :tv_series | :movie_series | :video_object`
    * `:present_only` — when `true`, keep only items with `present? == true`
  """
  @spec read(keyword()) :: [BrowseItem.t()]
  def read(opts \\ []) do
    items =
      case :ets.whereis(@table) do
        :undefined -> read_from_db()
        _ref -> read_from_ets()
      end

    apply_filters(items, opts)
  end

  defp read_from_ets do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {rank, _item} -> rank end)
    |> Enum.map(fn {_rank, item} -> item end)
  end

  defp read_from_db do
    Browser.fetch_all_typed_entries()
    |> Enum.take(@max_items)
    |> Enum.map(&to_view_model/1)
    |> Enum.with_index(fn item, rank -> %{item | rank: rank} end)
  end

  defp apply_filters(items, []), do: items

  defp apply_filters(items, opts) do
    items
    |> filter_by_kind(Keyword.get(opts, :kind))
    |> filter_present_only(Keyword.get(opts, :present_only, false))
  end

  defp filter_by_kind(items, nil), do: items
  defp filter_by_kind(items, kind), do: Enum.filter(items, &(&1.kind == kind))

  defp filter_present_only(items, false), do: items
  defp filter_present_only(items, true), do: Enum.filter(items, & &1.present?)

  # `entry` is the rich `%{entity:, progress:, progress_records:}` map
  # produced by `Browser.fetch_all_typed_entries/0` — the entity is the
  # normalized view-model from `EntityShape.to_view_model/2` (a map with
  # :id, :type, :name, :date_published, :images, ...). The projection
  # collapses this into the minimal BrowseItem shape; consumers that
  # need progress / availability / playback enrich per-row via their
  # own LiveView state (see ADR-041's decoupling principle).
  defp to_view_model(%{entity: entity}) do
    %BrowseItem{
      id: entity.id,
      kind: entity.type,
      name: entity.name,
      date_published: date_published_from(entity.date_published),
      year: year_from(entity.date_published),
      poster_url: poster_url_from(entity),
      present?: true,
      rank: nil
    }
  end

  defp date_published_from(%Date{} = date), do: date
  defp date_published_from(_), do: nil

  defp year_from(%Date{year: year}), do: year
  defp year_from(_), do: nil

  defp poster_url_from(%{images: images}) when is_list(images) do
    case Enum.find(images, &(&1.role == "poster")) do
      %{content_url: content_url} when is_binary(content_url) ->
        "/media-images/#{content_url}"

      _ ->
        nil
    end
  end

  defp poster_url_from(_), do: nil

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:ordered_set, :public, :named_table, read_concurrency: true])

      _ref ->
        :ok
    end
  end
end
