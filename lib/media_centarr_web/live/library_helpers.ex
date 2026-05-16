defmodule MediaCentarrWeb.LibraryHelpers do
  @moduledoc """
  Pure helpers for manipulating the LibraryLive grid — filtering,
  sorting, tab counts, and the reload strategy used after a batch of
  entity changes.

  Operates on lists of `MediaCentarr.Library.Views.BrowseItem` structs
  produced by the Browse projection (Library Schema v2 Phase 3.1).
  Progress is supplied separately via the LibraryLive `progress_by_id`
  assign (a map of `entity_id => ProgressSummary.t()`); helpers that
  depend on progress receive that map as an explicit argument.

  Display formatting lives in `LibraryFormatters`, progress and resume
  logic in `LibraryProgress`, and storage-availability state in
  `LibraryAvailability`.
  """

  alias MediaCentarr.Library.Views.BrowseItem

  @movie_kinds [:movie, :movie_series, :video_object]

  # --- Filtering ---

  @spec filtered_by_tab([BrowseItem.t()], :all | :movies | :tv) :: [BrowseItem.t()]
  def filtered_by_tab(entries, :all), do: entries

  def filtered_by_tab(entries, :movies) do
    Enum.filter(entries, &(&1.kind in @movie_kinds))
  end

  def filtered_by_tab(entries, :tv) do
    Enum.filter(entries, &(&1.kind == :tv_series))
  end

  @spec filtered_by_in_progress([BrowseItem.t()], map(), boolean()) :: [BrowseItem.t()]
  def filtered_by_in_progress(entries, _progress_by_id, false), do: entries

  def filtered_by_in_progress(entries, progress_by_id, true) do
    Enum.filter(entries, fn entry ->
      MediaCentarrWeb.LibraryProgress.in_progress_summary?(Map.get(progress_by_id, entry.id))
    end)
  end

  @spec filtered_by_text([BrowseItem.t()], String.t()) :: [BrowseItem.t()]
  def filtered_by_text(entries, ""), do: entries

  def filtered_by_text(entries, text) do
    needle = String.downcase(text)
    Enum.filter(entries, &name_matches?(&1.name, needle))
  end

  defp name_matches?(nil, _needle), do: false
  defp name_matches?(name, needle), do: String.contains?(String.downcase(name), needle)

  # --- Sorting ---

  @spec sorted_by([BrowseItem.t()], :alpha | :year | :recent) :: [BrowseItem.t()]
  def sorted_by(entries, :alpha) do
    Enum.sort_by(entries, fn entry -> String.downcase(entry.name || "") end)
  end

  def sorted_by(entries, :year) do
    # Module-aware sort: Erlang term-order on `%Date{}` is calendar →
    # day → month → year (lexicographic on internal struct fields),
    # which would silently mis-order entries from different months.
    # `{:desc, Date}` forces `Date.compare/2`.
    Enum.sort_by(
      entries,
      fn entry -> entry.date_published || ~D[0001-01-01] end,
      {:desc, Date}
    )
  end

  # The Browse projection already orders by `inserted_at desc`. `:recent`
  # is the implicit display order — return entries as-is rather than
  # re-sorting on a field BrowseItem doesn't carry.
  def sorted_by(entries, :recent), do: entries

  @epoch ~U[2000-01-01 00:00:00Z]

  @doc """
  Sorts entries by most-recently-watched descending. Entries with no
  recorded progress sort last. Used by the `?in_progress=1` filter.
  """
  @spec sorted_by_last_watched([BrowseItem.t()], map()) :: [BrowseItem.t()]
  def sorted_by_last_watched(entries, progress_by_id) do
    # Module-aware sort: `%DateTime{}` term-order is not chronological;
    # `{:desc, DateTime}` forces `DateTime.compare/2`.
    Enum.sort_by(
      entries,
      fn entry ->
        case Map.get(progress_by_id, entry.id) do
          %{last_watched_at: %DateTime{} = at} -> at
          _ -> @epoch
        end
      end,
      {:desc, DateTime}
    )
  end

  # --- Tab counts ---

  @spec tab_counts([BrowseItem.t()]) :: %{
          all: non_neg_integer(),
          movies: non_neg_integer(),
          tv: non_neg_integer()
        }
  def tab_counts(entries) do
    Enum.reduce(entries, %{all: 0, movies: 0, tv: 0}, fn entry, counts ->
      counts = %{counts | all: counts.all + 1}

      cond do
        entry.kind in @movie_kinds ->
          %{counts | movies: counts.movies + 1}

        entry.kind == :tv_series ->
          %{counts | tv: counts.tv + 1}

        true ->
          counts
      end
    end)
  end

  # --- Reload strategy ---

  @doc """
  Decides whether the library grid stream needs a full reset or can be
  updated surgically after a batch of entity changes.

  Additions require a full `reset_stream` because `stream_insert/3`
  without an `:at` option appends, which misplaces new entries under
  any non-trivial sort order. Pure deletions and in-place updates are
  handled surgically by `touch_stream_entries/2` — its `entry == nil`
  branch issues `stream_delete_by_dom_id` for IDs that were removed
  from the entries map.

  This keeps the common case (file removed from disk → one card
  disappears) from tearing down the entire grid's DOM, which is
  user-visible as a flash across every item on screen.
  """
  @spec reload_strategy(%{new_entries: list(), changed_ids: MapSet.t()}) ::
          :reset | {:touch, list()}
  def reload_strategy(%{new_entries: [_ | _]}), do: :reset

  def reload_strategy(%{new_entries: [], changed_ids: changed_ids}),
    do: {:touch, MapSet.to_list(changed_ids)}
end
