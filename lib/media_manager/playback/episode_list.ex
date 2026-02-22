defmodule MediaManager.Playback.EpisodeList do
  @moduledoc """
  Shared helpers for walking a TV series entity's seasons and episodes.
  Used by Resume, ProgressSummary, and PlaybackChannel.
  """

  @doc """
  Returns a flat list of `{season_number, episode_number, content_url}` tuples
  for episodes that have a content_url, sorted by season then episode.
  """
  def list_available(entity) do
    (entity.seasons || [])
    |> Enum.sort_by(& &1.season_number)
    |> Enum.flat_map(fn season ->
      (season.episodes || [])
      |> Enum.filter(& &1.content_url)
      |> Enum.sort_by(& &1.episode_number)
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
