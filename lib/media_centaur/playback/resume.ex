defmodule MediaCentaur.Playback.Resume do
  @moduledoc """
  Pure function that determines what to play and where to start for a given entity
  and its watch progress records. No DB access, no side effects.
  """

  alias MediaCentaur.Playback.{EpisodeList, MovieList}

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
      |> Enum.map(fn {ordinal, _movie_id, url} -> {0, ordinal, url} end)

    progress_by_key = EpisodeList.index_progress_by_key(progress_records)
    walk_ordered_items(items, progress_records, progress_by_key)
  end

  # TVSeries — walk episodes in order, find resume point
  defp resolve_tv_series(entity, progress_records) do
    items = EpisodeList.list_available(entity)
    progress_by_key = EpisodeList.index_progress_by_key(progress_records)
    walk_ordered_items(items, progress_records, progress_by_key)
  end

  # Shared walking logic for ordered item lists.
  # Items are {key_a, key_b, url} tuples. Progress is indexed by {key_a, key_b}.
  defp walk_ordered_items([], _progress_records, _progress_by_key) do
    {:no_playable_content}
  end

  defp walk_ordered_items(items, [], _progress_by_key) do
    {_a, _b, url} = List.first(items)
    {:play_next, url, 0.0}
  end

  defp walk_ordered_items(items, progress_records, progress_by_key) do
    most_recent =
      Enum.max_by(progress_records, & &1.last_watched_at, DateTime, fn -> nil end)

    case most_recent do
      nil ->
        {_a, _b, url} = List.first(items)
        {:play_next, url, 0.0}

      record ->
        if record.completed do
          advance_from(record, items, progress_by_key)
        else
          key = {record.season_number, record.episode_number}

          case find_item_url(items, key) do
            nil -> advance_from(record, items, progress_by_key)
            url -> {:resume, url, record.position_seconds || 0.0}
          end
        end
    end
  end

  defp advance_from(record, items, progress_by_key) do
    current_key = {record.season_number, record.episode_number}

    current_index =
      Enum.find_index(items, fn {a, b, _url} ->
        {a, b} == current_key
      end)

    case current_index do
      nil ->
        find_next_unwatched(items, progress_by_key)

      index ->
        remaining = Enum.drop(items, index + 1)

        case remaining do
          [] ->
            {_a, _b, first_url} = List.first(items)
            {:restart, first_url, 0.0}

          [{_a, _b, url} | _] ->
            {:play_next, url, 0.0}
        end
    end
  end

  defp find_next_unwatched(items, progress_by_key) do
    unwatched =
      Enum.find(items, fn {a, b, _url} ->
        not Map.has_key?(progress_by_key, {a, b})
      end)

    case unwatched do
      {_a, _b, url} ->
        {:play_next, url, 0.0}

      nil ->
        {_a, _b, first_url} = List.first(items)
        {:restart, first_url, 0.0}
    end
  end

  defp find_item_url(items, {key_a, key_b}) do
    case Enum.find(items, fn {a, b, _url} -> {a, b} == {key_a, key_b} end) do
      {_a, _b, url} -> url
      nil -> nil
    end
  end
end
