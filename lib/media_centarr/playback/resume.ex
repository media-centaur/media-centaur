defmodule MediaCentarr.Playback.Resume do
  @moduledoc """
  Pure function that determines what to play and where to start for a given entity
  and its watch progress records. No DB access, no side effects.
  """

  alias MediaCentarr.Playback.{EpisodeList, MovieList}

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

  # MovieSeries — walk child movies in order
  defp resolve_movie_series(entity, progress_records) do
    items =
      entity
      |> MovieList.list_available()
      |> Enum.map(fn {_ordinal, movie_id, url} -> {url, movie_id} end)

    progress_by_key = EpisodeList.index_progress_by_key(progress_records)
    walk_ordered_items(items, progress_records, progress_by_key)
  end

  # TVSeries — walk episodes in order, find resume point
  defp resolve_tv_series(entity, progress_records) do
    items =
      entity
      |> EpisodeList.list_available()
      |> Enum.map(fn {_season, _episode, url, episode_id} -> {url, episode_id} end)

    progress_by_key = EpisodeList.index_progress_by_key(progress_records)
    walk_ordered_items(items, progress_records, progress_by_key)
  end

  # Shared walking logic for ordered item lists.
  # Items are {url, fk_id} tuples. Progress is indexed by fk_id (episode_id or movie_id).
  defp walk_ordered_items([], _progress_records, _progress_by_key) do
    {:no_playable_content}
  end

  defp walk_ordered_items(items, [], _progress_by_key) do
    {url, _id} = List.first(items)
    {:play_next, url, 0.0}
  end

  defp walk_ordered_items(items, progress_records, progress_by_key) do
    most_recent =
      Enum.max_by(progress_records, & &1.last_watched_at, DateTime, fn -> nil end)

    case most_recent do
      nil ->
        {url, _id} = List.first(items)
        {:play_next, url, 0.0}

      record ->
        record_key = record.episode_id || record.movie_id

        if record.completed do
          advance_from(record_key, items, progress_by_key)
        else
          case find_item_url(items, record_key) do
            nil -> advance_from(record_key, items, progress_by_key)
            url -> {:resume, url, record.position_seconds || 0.0}
          end
        end
    end
  end

  defp advance_from(current_key, items, progress_by_key) do
    current_index =
      Enum.find_index(items, fn {_url, id} -> id == current_key end)

    case current_index do
      nil ->
        find_next_unwatched(items, progress_by_key)

      index ->
        remaining = Enum.drop(items, index + 1)

        case remaining do
          [] ->
            {first_url, _id} = List.first(items)
            {:restart, first_url, 0.0}

          [{url, _id} | _] ->
            {:play_next, url, 0.0}
        end
    end
  end

  defp find_next_unwatched(items, progress_by_key) do
    unwatched =
      Enum.find(items, fn {_url, id} ->
        not Map.has_key?(progress_by_key, id)
      end)

    case unwatched do
      {url, _id} ->
        {:play_next, url, 0.0}

      nil ->
        {first_url, _id} = List.first(items)
        {:restart, first_url, 0.0}
    end
  end

  defp find_item_url(items, key) do
    case Enum.find(items, fn {_url, id} -> id == key end) do
      {url, _id} -> url
      nil -> nil
    end
  end
end
