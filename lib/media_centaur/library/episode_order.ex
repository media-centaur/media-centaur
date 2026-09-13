defmodule MediaCentaur.Library.EpisodeOrder do
  @moduledoc """
  Ordering and position lookup over a TV series entity's seasons and
  episodes: sorting, the playable sequence, and finding an episode by
  position or by content URL. Used by Resume, ResumeTarget and
  ProgressSummary.

  The movie-collection parallel is `MediaCentaur.Library.MovieOrder`.
  Reading a progress record — its container id, its watch state, indexing
  a list of them — belongs to `MediaCentaur.Library.ProgressRecords`, and
  lived here until 2026-09-13.
  """

  @doc "Sorts seasons by season_number."
  def sort_seasons(seasons) when is_list(seasons), do: Enum.sort_by(seasons, & &1.season_number)
  def sort_seasons(_), do: []

  @doc "Sorts episodes by episode_number."
  def sort_episodes(episodes) when is_list(episodes), do: Enum.sort_by(episodes, & &1.episode_number)

  def sort_episodes(_), do: []

  @doc """
  Returns a flat list of `{season_number, episode_number, content_url, episode_id}` tuples
  for episodes that have a content_url, sorted by season then episode.
  """
  def list_available(entity) do
    (entity.seasons || [])
    |> sort_seasons()
    |> Enum.flat_map(fn season ->
      (season.episodes || [])
      |> Enum.filter(& &1.content_url)
      |> sort_episodes()
      |> Enum.map(&{season.season_number, &1.episode_number, &1.content_url, &1.id})
    end)
  end

  @doc """
  Returns the episode that immediately follows `episode_id` in season/episode
  order, as a `{season_number, episode_number, content_url, episode_id}` tuple,
  or `nil` when there is no playable successor.

  The walk is over *all* episodes, not just downloaded ones: when the
  literally-next episode has no `content_url`, the result is `nil` rather
  than the next available episode — auto-advance must never skip a gap in
  story order. `nil` is also returned after the final episode and for an
  unknown `episode_id`.
  """
  def next_episode_after(entity, episode_id) do
    ordered =
      (entity.seasons || [])
      |> sort_seasons()
      |> Enum.flat_map(fn season ->
        season.episodes
        |> sort_episodes()
        |> Enum.map(&{season.season_number, &1.episode_number, &1.content_url, &1.id})
      end)

    case Enum.find_index(ordered, fn {_season, _episode, _url, id} -> id == episode_id end) do
      nil ->
        nil

      index ->
        case Enum.at(ordered, index + 1) do
          {_season, _episode, nil, _id} -> nil
          next -> next
        end
    end
  end

  @doc """
  Finds the name of a specific episode in an entity.

  Returns the episode name string or `nil`.
  """
  def find_episode_name(_entity, nil, _episode_number), do: nil
  def find_episode_name(_entity, _season_number, nil), do: nil

  def find_episode_name(entity, season_number, episode_number) do
    (entity.seasons || [])
    |> Enum.find(&(&1.season_number == season_number))
    |> case do
      nil -> nil
      season -> Enum.find(season.episodes || [], &(&1.episode_number == episode_number))
    end
    |> case do
      nil -> nil
      episode -> episode.name
    end
  end

  @doc """
  Finds the `{season_number, episode_number}` for an episode matching a content_url.

  Returns `{season_number, episode_number}` or `nil`.
  """
  def find_by_content_url(entity, content_url) do
    Enum.find_value(entity.seasons || [], fn season ->
      Enum.find_value(season.episodes || [], fn episode ->
        if episode.content_url == content_url do
          {season.season_number, episode.episode_number}
        end
      end)
    end)
  end
end
