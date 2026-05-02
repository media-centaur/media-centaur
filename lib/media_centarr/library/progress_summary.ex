defmodule MediaCentarr.Library.ProgressSummary do
  @moduledoc """
  Computes a display-ready progress summary for an entity given its watch progress records.
  Pure function — no DB or side effects.
  """

  alias MediaCentarr.Library.{EpisodeList, MovieList}

  @type t :: %{
          current_episode: %{season: integer(), episode: integer()} | nil,
          episode_position_seconds: float(),
          episode_duration_seconds: float(),
          episodes_completed: integer(),
          episodes_total: integer()
        }

  @doc """
  Returns a progress summary map for the given entity and its progress records,
  or `nil` when no progress records exist.
  """
  @spec compute(map(), [map()]) :: t() | nil
  def compute(_entity, []), do: nil

  def compute(entity, progress_records) do
    case entity.type do
      :tv_series -> compute_tv_series(entity, progress_records)
      :movie_series -> compute_movie_series(entity, progress_records)
      _other -> compute_single(progress_records)
    end
  end

  # Movie, MovieSeries (single child), VideoObject — one playable item
  defp compute_single(progress_records) do
    progress = Enum.max_by(progress_records, & &1.last_watched_at, DateTime, fn -> nil end)
    progress = progress || List.first(progress_records)

    %{
      current_episode: nil,
      episode_position_seconds: progress.position_seconds || 0.0,
      episode_duration_seconds: progress.duration_seconds || 0.0,
      episodes_completed: if(progress.completed, do: 1, else: 0),
      episodes_total: 1
    }
  end

  defp compute_tv_series(entity, progress_records) do
    items =
      entity
      |> EpisodeList.list_available()
      |> Enum.map(fn {season, episode, _url, episode_id} ->
        {%{season: season, episode: episode}, episode_id}
      end)

    episodes_total = length(items)
    episodes_completed = Enum.count(progress_records, & &1.completed)

    {current_episode, current_progress} = find_current_item(items, progress_records)

    %{
      current_episode: current_episode,
      episode_position_seconds: position_for(current_progress),
      episode_duration_seconds: duration_for(current_progress),
      episodes_completed: episodes_completed,
      episodes_total: episodes_total
    }
  end

  defp compute_movie_series(entity, progress_records) do
    items =
      entity
      |> MovieList.list_available()
      |> Enum.map(fn {ordinal, movie_id, _url} ->
        {%{season: 0, episode: ordinal}, movie_id}
      end)

    episodes_total = length(items)
    valid_ids = MapSet.new(items, fn {_label, id} -> id end)

    episodes_completed =
      Enum.count(progress_records, fn record ->
        record.completed and MapSet.member?(valid_ids, record.movie_id)
      end)

    {current_episode, current_progress} = find_current_item(items, progress_records)

    %{
      current_episode: current_episode,
      episode_position_seconds: position_for(current_progress),
      episode_duration_seconds: duration_for(current_progress),
      episodes_completed: episodes_completed,
      episodes_total: episodes_total
    }
  end

  # Finds the "current" item to resume. Logic:
  # 1. Find the most recently watched progress record (by last_watched_at)
  # 2. If it's completed, advance to the next item in the available list
  # 3. If it's partial, that's the current item
  # 4. If no next item exists (series finished), return the last watched one
  #
  # Items are {label, fk_id} tuples. Labels are %{season:, episode:} maps for display.
  defp find_current_item(items, progress_records) do
    progress_by_key = EpisodeList.index_progress_by_key(progress_records)

    most_recent =
      Enum.max_by(progress_records, & &1.last_watched_at, DateTime, fn -> nil end)

    case most_recent do
      nil ->
        first_item_or_nil(items)

      record ->
        record_key = record.episode_id || record.movie_id

        cond do
          record.completed ->
            advance_from(record_key, items, progress_by_key)

          find_label_for_key(items, record_key) == nil ->
            # Partial record references an item that no longer exists
            # (e.g. episode delisted from the season). Fall back to the
            # first unwatched item rather than leaking the orphan's
            # position into the UI.
            first_unwatched_or_last(items, progress_by_key, record_key)

          true ->
            {find_label_for_key(items, record_key), record}
        end
    end
  end

  defp advance_from(current_key, items, progress_by_key) do
    current_index = Enum.find_index(items, fn {_label, id} -> id == current_key end)

    case current_index do
      nil ->
        first_unwatched_or_last(items, progress_by_key, current_key)

      index ->
        next_index = index + 1

        if next_index < length(items) do
          {label, fk_id} = Enum.at(items, next_index)
          next_progress = Map.get(progress_by_key, fk_id)
          {label, next_progress}
        else
          # Series finished — stay on the last item
          {label, _id} = Enum.at(items, index)
          fallback_progress = Map.get(progress_by_key, current_key)
          {label, fallback_progress}
        end
    end
  end

  defp first_unwatched_or_last(items, progress_by_key, fallback_key) do
    unwatched =
      Enum.find(items, fn {_label, id} -> not Map.has_key?(progress_by_key, id) end)

    case unwatched do
      {label, _id} ->
        {label, nil}

      nil ->
        fallback_label = find_label_for_key(items, fallback_key)
        fallback_progress = Map.get(progress_by_key, fallback_key)
        {fallback_label, fallback_progress}
    end
  end

  defp first_item_or_nil([{label, _id} | _]), do: {label, nil}
  defp first_item_or_nil([]), do: {nil, nil}

  defp find_label_for_key(items, key) do
    case Enum.find(items, fn {_label, id} -> id == key end) do
      {label, _id} -> label
      nil -> nil
    end
  end

  defp position_for(nil), do: 0.0
  defp position_for(progress), do: progress.position_seconds || 0.0

  defp duration_for(nil), do: 0.0
  defp duration_for(progress), do: progress.duration_seconds || 0.0
end
