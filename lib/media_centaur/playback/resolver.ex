defmodule MediaCentaur.Playback.Resolver do
  @moduledoc """
  Resolves a UUID into playback parameters.

  The UUID can identify any playable thing: a top-level Entity, an Episode,
  a child Movie, or an Extra. The resolver figures out what the UUID refers to,
  loads the necessary context, applies smart resume logic, and returns a
  `play_params` map suitable for `Sessions.play/1`.

  UUID resolution order:
  1. Entity — if series, run `Resume.resolve`; if single item, check progress
  2. Episode — load parent entity, check WatchProgress, resume if partial
  3. Movie (child) — load parent entity, check WatchProgress, resume if partial
  4. Extra — play from 0 (no progress tracking)
  """

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Helpers
  alias MediaCentaur.Playback.{EpisodeList, MovieList, Resume}

  @type play_params :: %{
          action: atom(),
          entity_id: String.t(),
          entity_name: String.t(),
          season_number: integer() | nil,
          episode_number: integer() | nil,
          episode_name: String.t() | nil,
          content_url: String.t(),
          start_position: float()
        }

  @doc """
  Resolves a UUID into playback parameters.

  Returns `{:ok, play_params}` or `{:error, reason}`.
  """
  @spec resolve(String.t()) :: {:ok, play_params()} | {:error, atom()}
  def resolve(uuid) do
    with {:error, :not_found} <- resolve_entity(uuid),
         {:error, :not_found} <- resolve_episode(uuid),
         {:error, :not_found} <- resolve_movie(uuid),
         {:error, :not_found} <- resolve_extra(uuid) do
      {:error, :not_found}
    end
  end

  # --- Entity resolution ---

  defp resolve_entity(uuid) do
    case Helpers.load_entity(uuid) do
      {:ok, entity} ->
        progress_records = load_progress(entity.id)
        resolve_entity_playback(entity, progress_records)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp resolve_entity_playback(entity, progress_records) do
    case Resume.resolve(entity, progress_records) do
      {:no_playable_content} ->
        {:error, :no_playable_content}

      {action, content_url, position} ->
        {season, episode, episode_name} =
          episode_context(action, entity, content_url, progress_records)

        {:ok,
         %{
           action: action,
           entity_id: entity.id,
           entity_name: entity.name,
           season_number: season,
           episode_number: episode,
           episode_name: episode_name,
           content_url: content_url,
           start_position: position
         }}
    end
  end

  # --- Episode resolution ---

  defp resolve_episode(uuid) do
    case Library.get_episode(uuid) do
      {:ok, episode} ->
        resolve_episode_playback(episode)

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp resolve_episode_playback(%{content_url: nil}), do: {:error, :no_playable_content}

  defp resolve_episode_playback(episode) do
    with {:ok, season} <- Library.get_season(episode.season_id),
         {:ok, entity} <- Helpers.load_entity(season.entity_id) do
      progress_records = load_progress(entity.id)

      progress_by_key = EpisodeList.index_progress_by_key(progress_records)
      key = {season.season_number, episode.episode_number}
      position = resume_position(progress_by_key, key)

      action = if position > 0.0, do: :resume, else: :play_episode

      {:ok,
       %{
         action: action,
         entity_id: entity.id,
         entity_name: entity.name,
         season_number: season.season_number,
         episode_number: episode.episode_number,
         episode_name: episode.name,
         content_url: episode.content_url,
         start_position: position
       }}
    else
      {:error, _} -> {:error, :not_found}
    end
  end

  # --- Movie (child) resolution ---

  defp resolve_movie(uuid) do
    case Library.get_movie(uuid) do
      {:ok, movie} ->
        resolve_movie_playback(movie)

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp resolve_movie_playback(%{content_url: nil}), do: {:error, :no_playable_content}

  defp resolve_movie_playback(movie) do
    case Helpers.load_entity(movie.entity_id) do
      {:ok, entity} ->
        progress_records = load_progress(entity.id)
        available = MovieList.list_available(entity)

        ordinal =
          case Enum.find(available, fn {_ord, id, _url} -> id == movie.id end) do
            {ord, _id, _url} -> ord
            nil -> nil
          end

        if ordinal do
          progress_by_key = EpisodeList.index_progress_by_key(progress_records)
          key = {0, ordinal}
          position = resume_position(progress_by_key, key)

          action = if position > 0.0, do: :resume, else: :play_movie

          {:ok,
           %{
             action: action,
             entity_id: entity.id,
             entity_name: entity.name,
             season_number: 0,
             episode_number: ordinal,
             episode_name: movie.name,
             content_url: movie.content_url,
             start_position: position
           }}
        else
          {:error, :no_playable_content}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  # --- Extra resolution ---

  defp resolve_extra(uuid) do
    case Library.get_extra(uuid) do
      {:ok, extra} ->
        resolve_extra_playback(extra)

      {:error, _} ->
        {:error, :not_found}
    end
  end

  defp resolve_extra_playback(%{content_url: nil}), do: {:error, :no_playable_content}

  defp resolve_extra_playback(extra) do
    entity_name =
      case Helpers.load_entity(extra.entity_id) do
        {:ok, entity} -> entity.name
        _ -> nil
      end

    {:ok,
     %{
       action: :play_extra,
       entity_id: extra.entity_id,
       entity_name: entity_name,
       season_number: nil,
       episode_number: nil,
       episode_name: extra.name,
       content_url: extra.content_url,
       start_position: 0.0
     }}
  end

  # --- Shared helpers ---

  defp load_progress(entity_id) do
    Library.list_watch_progress_for_entity!(entity_id)
  end

  defp resume_position(progress_by_key, key) do
    case Map.get(progress_by_key, key) do
      nil -> 0.0
      %{completed: true} -> 0.0
      %{position_seconds: pos} when is_number(pos) -> pos
      _ -> 0.0
    end
  end

  defp episode_context(_action, %{type: :movie_series} = entity, content_url, _progress_records) do
    case MovieList.find_by_content_url(entity, content_url) do
      {ordinal, _movie_id, movie_name} -> {0, ordinal, movie_name}
      nil -> {nil, nil, nil}
    end
  end

  defp episode_context(:resume, entity, _url, progress_records) do
    {season, episode} = most_recent_episode(progress_records)
    episode_name = EpisodeList.find_episode_name(entity, season, episode)
    {season, episode, episode_name}
  end

  defp episode_context(_action, entity, content_url, _progress_records) do
    case EpisodeList.find_by_content_url(entity, content_url) do
      {season, episode} ->
        episode_name = EpisodeList.find_episode_name(entity, season, episode)
        {season, episode, episode_name}

      nil ->
        {nil, nil, nil}
    end
  end

  defp most_recent_episode([]), do: {nil, nil}

  defp most_recent_episode(progress_records) do
    most_recent = Enum.max_by(progress_records, & &1.last_watched_at, DateTime, fn -> nil end)
    if most_recent, do: {most_recent.season_number, most_recent.episode_number}, else: {nil, nil}
  end
end
