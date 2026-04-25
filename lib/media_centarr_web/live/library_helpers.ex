defmodule MediaCentarrWeb.LibraryHelpers do
  @moduledoc """
  Pure helpers for manipulating the library entries list — filtering,
  sorting, tab counts, surgical entry updates, and the reload strategy
  used after a batch of entity changes.

  Display formatting lives in `LibraryFormatters`, progress and resume
  logic in `LibraryProgress`, and storage-availability state in
  `LibraryAvailability`.
  """

  @movie_types [:movie, :movie_series, :video_object]

  # --- Surgical entry updates ---

  @doc """
  Applies `updater` to a single entry identified by `entity_id` without
  rebuilding the `entries_by_id` map from scratch.

  Returns `{:ok, {new_entries, new_entries_by_id}}` on a hit, or
  `:not_found` when the id is absent.

  Progress and extra-progress events affect one entity; this helper keeps
  the O(n) cost bounded to a single list walk instead of the walk plus
  the `Map.new/2` map-rebuild that `assign_entries/2` performs.
  """
  @spec apply_entry_update(list(), map(), String.t(), (map() -> map())) ::
          {:ok, {list(), map()}} | :not_found
  def apply_entry_update(entries, entries_by_id, entity_id, updater) do
    case Map.get(entries_by_id, entity_id) do
      nil ->
        :not_found

      existing ->
        updated = updater.(existing)

        new_entries =
          Enum.map(entries, fn
            %{entity: %{id: ^entity_id}} -> updated
            entry -> entry
          end)

        {:ok, {new_entries, Map.put(entries_by_id, entity_id, updated)}}
    end
  end

  # --- Filtering ---

  def filtered_by_tab(entries, :all), do: entries

  def filtered_by_tab(entries, :movies) do
    Enum.filter(entries, fn %{entity: entity} ->
      entity.type in @movie_types
    end)
  end

  def filtered_by_tab(entries, :tv) do
    Enum.filter(entries, fn %{entity: entity} -> entity.type == :tv_series end)
  end

  def filtered_by_text(entries, ""), do: entries

  def filtered_by_text(entries, text) do
    needle = String.downcase(text)

    Enum.filter(entries, fn %{entity: entity} ->
      name_matches?(entity.name, needle) || nested_matches?(entity, needle)
    end)
  end

  defp name_matches?(nil, _needle), do: false
  defp name_matches?(name, needle), do: String.contains?(String.downcase(name), needle)

  defp nested_matches?(%{type: :tv_series, seasons: seasons}, needle) when is_list(seasons) do
    Enum.any?(seasons, fn season ->
      Enum.any?(season.episodes || [], fn episode -> name_matches?(episode.name, needle) end)
    end)
  end

  defp nested_matches?(%{type: :movie_series, movies: movies}, needle) when is_list(movies) do
    Enum.any?(movies, fn movie -> name_matches?(movie.name, needle) end)
  end

  defp nested_matches?(_entity, _needle), do: false

  # --- Sorting ---

  def sorted_by(entries, :alpha) do
    Enum.sort_by(entries, fn entry -> String.downcase(entry.entity.name || "") end)
  end

  def sorted_by(entries, :year) do
    Enum.sort_by(
      entries,
      fn entry -> entry.entity.date_published || "" end,
      :desc
    )
  end

  def sorted_by(entries, :recent) do
    Enum.sort_by(
      entries,
      fn entry -> entry.entity.inserted_at || ~U[2000-01-01 00:00:00Z] end,
      {:desc, DateTime}
    )
  end

  # --- Tab counts ---

  def tab_counts(entries) do
    Enum.reduce(entries, %{all: 0, movies: 0, tv: 0}, fn %{entity: entity}, counts ->
      counts = %{counts | all: counts.all + 1}

      cond do
        entity.type in @movie_types ->
          %{counts | movies: counts.movies + 1}

        entity.type == :tv_series ->
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

  Additions require a full `reset_stream` because `stream_insert/3` without
  an `:at` option appends, which misplaces new entries under any non-trivial
  sort order. Pure deletions and in-place updates are handled surgically by
  `touch_stream_entries/2` — its `entry == nil` branch issues
  `stream_delete_by_dom_id` for IDs that were removed from `entries_by_id`.

  This keeps the common case (file removed from disk → one card disappears)
  from tearing down the entire grid's DOM, which is user-visible as a
  flash across every item on screen.
  """
  @spec reload_strategy(%{new_entries: list(), changed_ids: MapSet.t()}) ::
          :reset | {:touch, list()}
  def reload_strategy(%{new_entries: [_ | _]}), do: :reset

  def reload_strategy(%{new_entries: [], changed_ids: changed_ids}),
    do: {:touch, MapSet.to_list(changed_ids)}
end
