defmodule MediaCentaur.Playback.NextEpisode do
  @moduledoc """
  Resolves the episode to queue after the one currently playing (ADR-062).

  `resolve/2` answers "what does the mpv playlist get appended after this
  episode?" for the session's profile — the *literally next* episode in season/episode order
  (`EpisodeOrder.next_episode_after/2` never skips a story-order gap),
  carrying the profile's own resume position (ADR-078). Returns `:none` when the chain ends:
  auto-play is switched off, the episode is the last one, the successor
  isn't downloaded, or its file is missing from disk.

  The `MediaCentaur.Settings.Preferences.AutoPlayNextEpisode` setting is read here, at each
  queueing decision, so flipping it mid-session takes effect at the next
  episode boundary.

  The append command itself is the transport's (`Playback.Transport.queue/3`):
  the resume position rides a **per-entry** `start` option — the global
  `--start` launch flag (ADR-062) applies only to the first file and must
  never leak onto appended entries — and a remote player's entry carries
  the whole session option set, since its instance holds none.
  """

  alias MediaCentaur.Settings.Preferences.AutoPlayNextEpisode
  alias MediaCentaur.Library
  alias MediaCentaur.Library.{EntityShape, EpisodeOrder, TypeResolver}
  alias MediaCentaur.Playback.{Entry, PlayableFks}
  alias MediaCentaur.Library.ProgressRecords

  @doc """
  Returns `{:ok, entry}` for the episode that should follow `episode_id`
  for `profile_id`, or `:none` when nothing should be queued.
  """
  @spec resolve(String.t(), String.t()) :: {:ok, Entry.t()} | :none
  def resolve(profile_id, episode_id) when is_binary(profile_id) and is_binary(episode_id) do
    with true <- AutoPlayNextEpisode.enabled?(),
         {:ok, episode} <- Library.Episodes.fetch(episode_id),
         {:ok, season} <- Library.Seasons.fetch(episode.season_id),
         {:ok, tv_series} <-
           Library.Containers.fetch_with_associations(:tv_series, season.tv_series_id) do
      entity = EntityShape.to_entity_view(tv_series, :tv_series)

      progress_records =
        ProgressRecords.list_for_container(profile_id, :tv_series, season.tv_series_id)

      successor(entity, progress_records, episode_id)
    else
      _ -> :none
    end
  end

  @doc """
  Re-derives episode identity from the path mpv reports playing — the
  ADR-023 recovery discipline, used when a playlist advance lands on a
  file the session didn't queue itself (e.g. an entry queued before a
  backend restart). Returns `:none` when the path isn't an episode of
  the session's entity.
  """
  @spec identify(String.t(), String.t()) :: {:ok, Entry.t()} | :none
  def identify(entity_id, content_url) do
    case TypeResolver.resolve_container(entity_id,
           standalone_movie: false,
           preload: Library.Containers.full_preloads_by_type()
         ) do
      {:ok, type, record} ->
        entity = EntityShape.to_entity_view(record, type)

        case PlayableFks.resolve(entity, content_url) do
          %{episode_id: episode_id} when not is_nil(episode_id) ->
            {season_number, episode_number, episode_name} =
              PlayableFks.context_by_url(entity, content_url)

            {:ok,
             %Entry{
               entity_id: entity.id,
               entity_name: entity.name,
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
    case EpisodeOrder.next_episode_after(entity, episode_id) do
      nil ->
        :none

      {season_number, episode_number, content_url, next_episode_id} ->
        if File.exists?(content_url) do
          {:ok,
           %Entry{
             entity_id: entity.id,
             entity_name: entity.name,
             episode_id: next_episode_id,
             season_number: season_number,
             episode_number: episode_number,
             episode_name: EpisodeOrder.find_episode_name(entity, season_number, episode_number),
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
    |> ProgressRecords.index_progress_by_key()
    |> Map.get(episode_id)
    |> case do
      %{completed: true} -> 0.0
      %{position_seconds: position} when is_number(position) -> position
      _ -> 0.0
    end
  end
end
