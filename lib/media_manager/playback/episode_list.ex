defmodule MediaManager.Playback.EpisodeList do
  @moduledoc """
  Shared helpers for walking a TV series entity's seasons and episodes.
  Used by Resume and ProgressSummary.
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
end
