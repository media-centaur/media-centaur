defmodule MediaCentarr.Playback.EpisodeList do
  @moduledoc """
  Shared helpers for walking a TV series entity's seasons and episodes.
  Used by Resume and ProgressSummary.
  """

  @doc "Sorts seasons by season_number."
  def sort_seasons(seasons) when is_list(seasons), do: Enum.sort_by(seasons, & &1.season_number)
  def sort_seasons(_), do: []

  @doc "Sorts episodes by episode_number."
  def sort_episodes(episodes) when is_list(episodes),
    do: Enum.sort_by(episodes, & &1.episode_number)

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
  Indexes progress records by their FK — `episode_id` or `movie_id`.
  """
  def index_progress_by_key(progress_records) do
    Map.new(progress_records, fn record ->
      key = record.episode_id || record.movie_id
      {key, record}
    end)
  end

  @doc """
  Indexes progress by episode_id from episodes with preloaded `watch_progress`.

  Returns `%{episode_id => progress}` for episodes that have progress records.
  Expects a flat list of episode structs with `:watch_progress` preloaded.
  """
  def index_progress_by_episode(episodes) when is_list(episodes) do
    episodes
    |> Enum.filter(&progress_loaded?/1)
    |> Map.new(fn episode -> {episode.id, episode.watch_progress} end)
  end

  def index_progress_by_episode(_), do: %{}

  @doc """
  Finds the content_url for a specific season/episode in an entity.

  Returns `{:ok, url}` or `{:error, :invalid_episode}`.
  """
  def find_content_url(entity, season_number, episode_number) do
    with %{} = season <- Enum.find(entity.seasons || [], &(&1.season_number == season_number)),
         %{} = episode <-
           Enum.find(season.episodes || [], &(&1.episode_number == episode_number)),
         url when not is_nil(url) <- episode.content_url do
      {:ok, url}
    else
      _ -> {:error, :invalid_episode}
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

  defp progress_loaded?(%{watch_progress: %Ecto.Association.NotLoaded{}}), do: false
  defp progress_loaded?(%{watch_progress: nil}), do: false
  defp progress_loaded?(%{watch_progress: _}), do: true
  defp progress_loaded?(_), do: false
end
