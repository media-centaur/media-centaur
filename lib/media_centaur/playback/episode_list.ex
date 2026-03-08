defmodule MediaCentaur.Playback.EpisodeList do
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
  Returns a flat list of `{season_number, episode_number, content_url}` tuples
  for episodes that have a content_url, sorted by season then episode.
  """
  def list_available(entity) do
    (entity.seasons || [])
    |> sort_seasons()
    |> Enum.flat_map(fn season ->
      (season.episodes || [])
      |> Enum.filter(& &1.content_url)
      |> sort_episodes()
      |> Enum.map(&{season.season_number, &1.episode_number, &1.content_url})
    end)
  end

  @doc """
  Indexes progress records by `{season_number, episode_number}` key.
  """
  def index_progress_by_key(progress_records) do
    Map.new(progress_records, fn record ->
      {{record.season_number, record.episode_number}, record}
    end)
  end

  @doc """
  Finds the content_url for a specific season/episode in an entity.

  Returns `{:ok, url}` or `{:error, :invalid_episode}`.
  """
  def find_content_url(entity, season_number, episode_number) do
    result =
      (entity.seasons || [])
      |> Enum.find(&(&1.season_number == season_number))
      |> case do
        nil -> nil
        season -> Enum.find(season.episodes || [], &(&1.episode_number == episode_number))
      end
      |> case do
        nil -> nil
        episode -> episode.content_url
      end

    case result do
      nil -> {:error, :invalid_episode}
      url -> {:ok, url}
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
