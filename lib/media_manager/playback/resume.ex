defmodule MediaManager.Playback.Resume do
  @moduledoc """
  Pure function that determines what to play and where to start for a given entity
  and its watch progress records. No DB access, no side effects.
  """

  alias MediaManager.Playback.EpisodeList

  @type result ::
          {:resume, String.t(), float()}
          | {:play_next, String.t(), float()}
          | {:restart, String.t(), float()}
          | {:no_playable_content}

  @doc """
  Given an entity and its progress records, returns a playback action.

  ## Return values

    * `{:resume, content_url, position_seconds}` — partial progress, pick up where left off
    * `{:play_next, content_url, 0.0}` — play next unwatched item from the start
    * `{:restart, content_url, 0.0}` — everything completed, restart from beginning
    * `{:no_playable_content}` — no content_url found anywhere
  """
  @spec resolve(map(), [map()]) :: result()
  def resolve(entity, progress_records) do
    case entity.type do
      :tv_series -> resolve_tv_series(entity, progress_records)
      :movie_series -> resolve_movie_series(entity, progress_records)
      _other -> resolve_single(entity, progress_records)
    end
  end

  # Movie / VideoObject — single playable item on the entity itself
  defp resolve_single(entity, progress_records) do
    case entity.content_url do
      nil -> {:no_playable_content}
      url -> resolve_single_url(url, progress_records)
    end
  end

  defp resolve_single_url(url, []) do
    {:play_next, url, 0.0}
  end

  defp resolve_single_url(url, progress_records) do
    progress = List.first(progress_records)

    if progress.completed do
      {:play_next, url, 0.0}
    else
      {:resume, url, progress.position_seconds || 0.0}
    end
  end

  # MovieSeries — find first child movie with content_url
  defp resolve_movie_series(entity, progress_records) do
    movies =
      (entity.movies || [])
      |> Enum.filter(& &1.content_url)
      |> Enum.sort_by(fn movie -> {movie.position || 0, movie.date_published || ""} end)

    case movies do
      [] -> {:no_playable_content}
      [first_movie | _] -> resolve_single_url(first_movie.content_url, progress_records)
    end
  end

  # TVSeries — walk episodes in order, find resume point
  defp resolve_tv_series(entity, progress_records) do
    episodes = EpisodeList.list_available(entity)

    case episodes do
      [] -> {:no_playable_content}
      _ -> resolve_tv_episodes(episodes, progress_records)
    end
  end

  defp resolve_tv_episodes(episodes, []) do
    {_season, _episode, url} = List.first(episodes)
    {:play_next, url, 0.0}
  end

  defp resolve_tv_episodes(episodes, progress_records) do
    progress_by_key = EpisodeList.index_progress_by_key(progress_records)

    most_recent =
      Enum.max_by(progress_records, & &1.last_watched_at, DateTime, fn -> nil end)

    case most_recent do
      nil ->
        {_season, _episode, url} = List.first(episodes)
        {:play_next, url, 0.0}

      record ->
        if record.completed do
          advance_from(record, episodes, progress_by_key)
        else
          key = {record.season_number, record.episode_number}

          case find_episode_url(episodes, key) do
            nil -> advance_from(record, episodes, progress_by_key)
            url -> {:resume, url, record.position_seconds || 0.0}
          end
        end
    end
  end

  defp advance_from(record, episodes, progress_by_key) do
    current_key = {record.season_number, record.episode_number}
    current_index = Enum.find_index(episodes, fn {s, e, _url} -> {s, e} == current_key end)

    case current_index do
      nil ->
        find_next_unwatched(episodes, progress_by_key)

      index ->
        remaining = Enum.drop(episodes, index + 1)

        case find_next_with_url(remaining) do
          nil ->
            # All episodes after current are exhausted — restart from beginning
            {_s, _e, first_url} = List.first(episodes)
            {:restart, first_url, 0.0}

          {_s, _e, url} ->
            {:play_next, url, 0.0}
        end
    end
  end

  defp find_next_unwatched(episodes, progress_by_key) do
    unwatched =
      Enum.find(episodes, fn {s, e, _url} ->
        not Map.has_key?(progress_by_key, {s, e})
      end)

    case unwatched do
      {_s, _e, url} ->
        {:play_next, url, 0.0}

      nil ->
        # All watched — restart
        {_s, _e, first_url} = List.first(episodes)
        {:restart, first_url, 0.0}
    end
  end

  defp find_next_with_url([]), do: nil
  defp find_next_with_url([{s, e, url} | _rest]), do: {s, e, url}

  defp find_episode_url(episodes, {season, episode}) do
    case Enum.find(episodes, fn {s, e, _url} -> {s, e} == {season, episode} end) do
      {_s, _e, url} -> url
      nil -> nil
    end
  end
end
