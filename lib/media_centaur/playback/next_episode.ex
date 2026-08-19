defmodule MediaCentaur.Playback.NextEpisode do
  @moduledoc """
  Resolves the episode to queue after the one currently playing (ADR-062).

  `resolve/1` answers "what does the mpv playlist get appended after this
  episode?" — the *literally next* episode in season/episode order
  (`EpisodeList.next_episode_after/2` never skips a story-order gap),
  carrying its own resume position. Returns `:none` when the chain ends:
  auto-play is switched off, the episode is the last one, the successor
  isn't downloaded, or its file is missing from disk.

  The `MediaCentaur.Settings.Preferences.AutoPlayNextEpisode` setting is read here, at each
  queueing decision, so flipping it mid-session takes effect at the next
  episode boundary.

  `loadfile_command/1` builds the IPC command for the append. The resume
  position rides a **per-entry** `start` option — the global `--start`
  launch flag (ADR-013) applies only to the first file and must never
  leak onto appended entries. The 5-argument `loadfile` form (with the
  insertion index) requires mpv ≥ 0.38; entries starting at zero use the
  plain 3-argument form.
  """

  alias MediaCentaur.Settings.Preferences.AutoPlayNextEpisode
  alias MediaCentaur.Library
  alias MediaCentaur.Library.{EntityShape, EpisodeList, TypeResolver}
  alias MediaCentaur.Playback.PlayableFks

  @type queue_item :: %{
          episode_id: String.t(),
          season_number: integer(),
          episode_number: integer(),
          episode_name: String.t() | nil,
          content_url: String.t(),
          start_position: float()
        }

  @doc """
  Returns `{:ok, queue_item}` for the episode that should follow
  `episode_id`, or `:none` when nothing should be queued.
  """
  @spec resolve(String.t()) :: {:ok, queue_item()} | :none
  def resolve(episode_id) do
    with true <- AutoPlayNextEpisode.enabled?(),
         {:ok, episode} <- Library.Episodes.fetch(episode_id),
         {:ok, season} <- Library.Seasons.fetch(episode.season_id),
         {:ok, tv_series} <-
           Library.Containers.fetch_with_associations(:tv_series, season.tv_series_id) do
      entity = EntityShape.to_view_model(tv_series, :tv_series)
      progress_records = EntityShape.extract_progress(tv_series, :tv_series)
      successor(entity, progress_records, episode_id)
    else
      _ -> :none
    end
  end

  @doc """
  Builds the mpv IPC `loadfile` command that appends a queue item to the
  playlist.
  """
  @spec loadfile_command(%{content_url: String.t(), start_position: float()}) :: list()
  def loadfile_command(%{content_url: url, start_position: start}) when start > 0 do
    ["loadfile", url, "append", -1, "start=#{start}"]
  end

  def loadfile_command(%{content_url: url}), do: ["loadfile", url, "append"]

  @doc """
  Re-derives episode identity from the path mpv reports playing — the
  ADR-023 recovery discipline, used when a playlist advance lands on a
  file the session didn't queue itself (e.g. an entry queued before a
  backend restart). Returns `:none` when the path isn't an episode of
  the session's entity.
  """
  @spec identify(String.t(), String.t()) ::
          {:ok,
           %{
             episode_id: String.t(),
             season_number: integer() | nil,
             episode_number: integer() | nil,
             episode_name: String.t() | nil,
             content_url: String.t()
           }}
          | :none
  def identify(entity_id, content_url) do
    case TypeResolver.resolve_container(entity_id,
           standalone_movie: false,
           preload: Library.Containers.full_preloads_by_type()
         ) do
      {:ok, type, record} ->
        entity = EntityShape.to_view_model(record, type)

        case PlayableFks.resolve(entity, content_url) do
          %{episode_id: episode_id} when not is_nil(episode_id) ->
            {season_number, episode_number, episode_name} =
              PlayableFks.context_by_url(entity, content_url)

            {:ok,
             %{
               episode_id: episode_id,
               season_number: season_number,
               episode_number: episode_number,
               episode_name: episode_name,
               content_url: content_url
             }}

          _ ->
            :none
        end

      :not_found ->
        :none
    end
  end

  defp successor(entity, progress_records, episode_id) do
    case EpisodeList.next_episode_after(entity, episode_id) do
      nil ->
        :none

      {season_number, episode_number, content_url, next_episode_id} ->
        if File.exists?(content_url) do
          {:ok,
           %{
             episode_id: next_episode_id,
             season_number: season_number,
             episode_number: episode_number,
             episode_name: EpisodeList.find_episode_name(entity, season_number, episode_number),
             content_url: content_url,
             start_position: resume_position(progress_records, next_episode_id)
           }}
        else
          :none
        end
    end
  end

  defp resume_position(progress_records, episode_id) do
    progress_records
    |> EpisodeList.index_progress_by_key()
    |> Map.get(episode_id)
    |> case do
      %{completed: true} -> 0.0
      %{position_seconds: position} when is_number(position) -> position
      _ -> 0.0
    end
  end
end
