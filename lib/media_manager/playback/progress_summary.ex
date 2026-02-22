defmodule MediaManager.Playback.ProgressSummary do
  @moduledoc """
  Computes a display-ready progress summary for an entity given its watch progress records.
  Pure function — no DB or side effects.
  """

  alias MediaManager.Playback.EpisodeList

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
      _other -> compute_single(progress_records)
    end
  end

  # Movie, MovieSeries (single child), VideoObject — one playable item
  defp compute_single(progress_records) do
    progress = List.first(progress_records)

    %{
      current_episode: nil,
      episode_position_seconds: progress.position_seconds || 0.0,
      episode_duration_seconds: progress.duration_seconds || 0.0,
      episodes_completed: if(progress.completed, do: 1, else: 0),
      episodes_total: 1
    }
  end

  defp compute_tv_series(entity, progress_records) do
    episodes =
      entity
      |> EpisodeList.list_available()
      |> Enum.map(fn {season, episode, _url} -> {season, episode} end)

    episodes_total = length(episodes)
    episodes_completed = Enum.count(progress_records, & &1.completed)

    {current_episode, current_progress} = find_current_episode(episodes, progress_records)

    %{
      current_episode: current_episode,
      episode_position_seconds: position_for(current_progress),
      episode_duration_seconds: duration_for(current_progress),
      episodes_completed: episodes_completed,
      episodes_total: episodes_total
    }
  end

  # Finds the "current" episode to resume. Logic:
  # 1. Find the most recently watched progress record (by last_watched_at)
  # 2. If it's completed, advance to the next episode in the available list
  # 3. If it's partial, that's the current episode
  # 4. If no next episode exists (series finished), return the last watched one
  defp find_current_episode(episodes, progress_records) do
    progress_by_key = EpisodeList.index_progress_by_key(progress_records)

    most_recent =
      progress_records
      |> Enum.max_by(& &1.last_watched_at, DateTime, fn -> nil end)

    case most_recent do
      nil ->
        first_episode_or_nil(episodes)

      record ->
        if record.completed do
          advance_from(record, episodes, progress_by_key)
        else
          {%{season: record.season_number, episode: record.episode_number}, record}
        end
    end
  end

  defp advance_from(record, episodes, progress_by_key) do
    current_key = {record.season_number, record.episode_number}
    current_index = Enum.find_index(episodes, &(&1 == current_key))

    case current_index do
      nil ->
        # The completed episode isn't in the available list — return first unwatched
        first_unwatched_or_last(episodes, progress_by_key, record)

      index ->
        next_index = index + 1

        if next_index < length(episodes) do
          {season, episode} = Enum.at(episodes, next_index)
          next_progress = Map.get(progress_by_key, {season, episode})
          {%{season: season, episode: episode}, next_progress}
        else
          # Series finished — stay on the last episode
          {%{season: record.season_number, episode: record.episode_number}, record}
        end
    end
  end

  defp first_unwatched_or_last(episodes, progress_by_key, fallback_record) do
    unwatched =
      Enum.find(episodes, fn key -> not Map.has_key?(progress_by_key, key) end)

    case unwatched do
      {season, episode} ->
        {%{season: season, episode: episode}, nil}

      nil ->
        {%{season: fallback_record.season_number, episode: fallback_record.episode_number},
         fallback_record}
    end
  end

  defp first_episode_or_nil([{season, episode} | _]) do
    {%{season: season, episode: episode}, nil}
  end

  defp first_episode_or_nil([]), do: {nil, nil}

  defp position_for(nil), do: 0.0
  defp position_for(progress), do: progress.position_seconds || 0.0

  defp duration_for(nil), do: 0.0
  defp duration_for(progress), do: progress.duration_seconds || 0.0
end
