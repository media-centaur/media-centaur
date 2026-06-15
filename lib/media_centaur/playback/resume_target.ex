defmodule MediaCentaur.Playback.ResumeTarget do
  @moduledoc """
  Pure function that computes display hints for what will play when the user hits "play"
  on an entity. No DB access, no side effects.

  - `compute/2` returns the entity-level hint (`resumeTarget`)
  """

  alias MediaCentaur.Library.{EpisodeList, MovieList}
  alias MediaCentaur.Playback.Resume

  @doc """
  Computes the display hint for what will play next for this entity.

  Returns a map with `"action"` key ("begin" or "resume") and display fields,
  or `nil` when the entity is fully completed or has no playable content.
  """
  @spec compute(map(), [map()]) :: map() | nil
  def compute(entity, progress_records) do
    if !all_completed?(entity, progress_records) do
      case Resume.resolve(entity, progress_records) do
        {:play_next, url, _position} ->
          build_hint("begin", entity, url, nil)

        {:resume, url, position} ->
          progress = find_progress_for_url(entity, url, progress_records)
          duration = if progress, do: progress.duration_seconds || 0.0, else: 0.0
          build_hint("resume", entity, url, %{position: position, duration: duration})

        {:restart, _url, _position} ->
          nil

        {:no_playable_content} ->
          nil
      end
    end
  end

  # --- Private helpers ---

  defp all_completed?(%{type: :tv_series} = entity, progress_records) do
    episodes = EpisodeList.list_available(entity)
    episodes != [] and length(episodes) == Enum.count(progress_records, & &1.completed)
  end

  defp all_completed?(%{type: :movie_series} = entity, progress_records) do
    movies = MovieList.list_available(entity)
    movies != [] and length(movies) == Enum.count(progress_records, & &1.completed)
  end

  defp all_completed?(_entity, progress_records) do
    progress_records != [] and Enum.all?(progress_records, & &1.completed)
  end

  defp build_hint(action, %{type: :tv_series} = entity, url, timing) do
    case EpisodeList.find_by_content_url(entity, url) do
      {season_number, episode_number} ->
        name = EpisodeList.find_episode_name(entity, season_number, episode_number)

        episode =
          find_episode_struct(entity, season_number, episode_number)

        maybe_add_timing(
          %{
            "action" => action,
            "targetId" => episode && episode.id,
            "name" => name,
            "seasonNumber" => season_number,
            "episodeNumber" => episode_number
          },
          timing
        )

      nil ->
        nil
    end
  end

  defp build_hint(action, %{type: :movie_series} = entity, url, timing) do
    case MovieList.find_by_content_url(entity, url) do
      {ordinal, movie_id, movie_name} ->
        total = MovieList.total_available(entity)

        maybe_add_timing(
          %{
            "action" => action,
            "targetId" => movie_id,
            "name" => movie_name,
            "ordinal" => ordinal,
            "total" => total
          },
          timing
        )

      nil ->
        nil
    end
  end

  defp build_hint(action, entity, _url, timing) do
    maybe_add_timing(%{"action" => action, "name" => entity.name}, timing)
  end

  defp maybe_add_timing(hint, nil), do: hint

  defp maybe_add_timing(hint, %{position: position, duration: duration}) do
    hint
    |> Map.put("positionSeconds", position)
    |> Map.put("durationSeconds", duration)
  end

  defp find_progress_for_url(%{type: :tv_series} = entity, url, progress_records) do
    episode_id = find_episode_id_by_url(entity, url)

    if episode_id do
      Enum.find(progress_records, fn record ->
        EpisodeList.progress_container_id(record) == episode_id
      end)
    end
  end

  defp find_progress_for_url(%{type: :movie_series} = entity, url, progress_records) do
    case MovieList.find_by_content_url(entity, url) do
      {_ordinal, movie_id, _name} ->
        Enum.find(progress_records, fn record ->
          EpisodeList.progress_container_id(record) == movie_id
        end)

      nil ->
        nil
    end
  end

  defp find_progress_for_url(_entity, _url, progress_records) do
    List.first(progress_records)
  end

  defp find_episode_id_by_url(entity, url) do
    Enum.find_value(entity.seasons || [], fn season ->
      Enum.find_value(season.episodes || [], fn episode ->
        if episode.content_url == url, do: episode.id
      end)
    end)
  end

  defp find_episode_struct(entity, season_number, episode_number) do
    season = Enum.find(entity.seasons || [], &(&1.season_number == season_number))

    if season do
      Enum.find(season.episodes || [], &(&1.episode_number == episode_number))
    end
  end
end
