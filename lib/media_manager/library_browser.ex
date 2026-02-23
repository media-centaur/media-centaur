defmodule MediaManager.LibraryBrowser do
  @moduledoc """
  Data-fetching module for the library browser LiveView.
  Keeps the LiveView thin by centralizing all library queries and playback actions.
  """

  require MediaManager.Log, as: Log

  alias MediaManager.Library.{Entity, WatchProgress}
  alias MediaManager.Playback.{EpisodeList, Manager, ProgressSummary, Resume}

  @doc """
  Loads all entities with associations, computes progress summaries.

  Returns a list of `%{entity: entity, progress: summary, progress_records: records}`.
  """
  def fetch_entities do
    entities =
      Entity
      |> Ash.Query.for_read(:with_associations)
      |> Ash.Query.sort(name: :asc)
      |> Ash.read!()

    Log.info(:library, "loaded #{length(entities)} entities for browser")

    entities
    |> Enum.map(fn entity ->
      entity = pre_sort_children(entity)

      progress_records =
        Enum.sort_by(entity.watch_progress, &{&1.season_number, &1.episode_number})

      summary = ProgressSummary.compute(entity, progress_records)

      %{entity: entity, progress: summary, progress_records: progress_records}
    end)
    |> Enum.map(&maybe_unwrap_single_movie/1)
  end

  @doc """
  Smart play for an entity — resolves resume/next/restart via the Resume algorithm.
  """
  def play_entity(entity_id) do
    Log.info(:library, "play entity #{entity_id}")

    with {:ok, entity} <- load_entity(entity_id),
         progress_records <- load_progress(entity_id),
         {:ok, play_params} <- resolve_playback(entity, progress_records) do
      Manager.play(play_params)
    end
  end

  @doc """
  Play a specific episode of a TV series.
  """
  def play_episode(entity_id, season_number, episode_number) do
    with {:ok, entity} <- load_entity(entity_id),
         {:ok, content_url} <- EpisodeList.find_content_url(entity, season_number, episode_number) do
      episode_name = EpisodeList.find_episode_name(entity, season_number, episode_number)

      Manager.play(%{
        action: :play_episode,
        entity_id: entity_id,
        entity_name: entity.name,
        season_number: season_number,
        episode_number: episode_number,
        episode_name: episode_name,
        content_url: content_url,
        start_position: 0.0
      })
    end
  end

  @doc """
  Play a specific child movie of a movie series.
  """
  def play_movie(entity_id, movie_id) do
    with {:ok, entity} <- load_entity(entity_id) do
      movie = Enum.find(entity.movies || [], &(&1.id == movie_id))

      case movie do
        nil ->
          {:error, :not_found}

        %{content_url: nil} ->
          {:error, :no_playable_content}

        movie ->
          Manager.play(%{
            action: :play_movie,
            entity_id: entity_id,
            entity_name: entity.name,
            content_url: movie.content_url,
            start_position: 0.0
          })
      end
    end
  end

  # --- Private Helpers ---

  defp load_entity(entity_id) do
    case Ash.get(Entity, entity_id, action: :with_associations) do
      {:ok, entity} -> {:ok, entity}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp load_progress(entity_id) do
    WatchProgress
    |> Ash.Query.for_read(:for_entity, %{entity_id: entity_id})
    |> Ash.read!()
  end

  defp resolve_playback(entity, progress_records) do
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

  defp maybe_unwrap_single_movie(%{entity: %{type: :movie_series, movies: [movie]}} = entry) do
    entity =
      %{
        entry.entity
        | type: :movie,
          name: movie.name || entry.entity.name,
          date_published: movie.date_published || entry.entity.date_published,
          content_url: movie.content_url,
          movies: []
      }

    progress = ProgressSummary.compute(entity, entry.progress_records)
    %{entry | entity: entity, progress: progress}
  end

  defp maybe_unwrap_single_movie(entry), do: entry

  defp pre_sort_children(entity) do
    seasons =
      (entity.seasons || [])
      |> Enum.sort_by(& &1.season_number)
      |> Enum.map(fn season ->
        %{season | episodes: Enum.sort_by(season.episodes || [], & &1.episode_number)}
      end)

    movies = Enum.sort_by(entity.movies || [], &{&1.position || 0, &1.date_published || ""})

    %{entity | seasons: seasons, movies: movies}
  end
end
