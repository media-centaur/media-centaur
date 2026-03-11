defmodule MediaCentaur.LibraryBrowser do
  @moduledoc """
  Data-fetching module for the library browser LiveView.
  Keeps the LiveView thin by centralizing all library queries and playback actions.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Playback.{EpisodeList, Manager, MovieList, ProgressSummary, Resolver}

  @doc """
  Loads all entities with associations, computes progress summaries.

  Returns a list of `%{entity: entity, progress: summary, progress_records: records}`.
  """
  def fetch_entities do
    import Ash.Expr

    entities =
      Library.list_entities_with_associations!(
        query: [
          sort: [name: :asc],
          filter:
            expr(
              not (exists(watched_files, true) and
                     not exists(watched_files, state == :complete))
            )
        ]
      )

    Log.info(:library, "loaded #{length(entities)} entities for browser")

    Enum.map(entities, fn entity ->
      entity = pre_sort_children(entity)

      progress_records =
        Enum.sort_by(entity.watch_progress, &{&1.season_number, &1.episode_number})

      summary = ProgressSummary.compute(entity, progress_records)

      %{entity: entity, progress: summary, progress_records: progress_records}
      |> maybe_unwrap_single_movie()
    end)
  end

  @doc """
  Loads specific entities by ID with full associations and progress.

  Returns `{updated_entries, gone_ids}` where `gone_ids` contains entity IDs
  that no longer exist or have all files absent.
  """
  def fetch_entries_by_ids(entity_ids) do
    import Ash.Expr

    entities =
      Library.list_entities_by_ids!(entity_ids,
        query: [
          filter:
            expr(
              not (exists(watched_files, true) and
                     not exists(watched_files, state == :complete))
            )
        ]
      )

    present_ids = MapSet.new(entities, & &1.id)
    requested = MapSet.new(entity_ids)
    gone_ids = MapSet.difference(requested, present_ids)

    entries =
      Enum.map(entities, fn entity ->
        entity = pre_sort_children(entity)

        progress_records =
          Enum.sort_by(entity.watch_progress, &{&1.season_number, &1.episode_number})

        summary = ProgressSummary.compute(entity, progress_records)

        %{entity: entity, progress: summary, progress_records: progress_records}
        |> maybe_unwrap_single_movie()
      end)

    {entries, gone_ids}
  end

  @doc """
  Smart play for any UUID — resolves the target and starts playback.
  """
  def play(uuid) do
    Log.info(:library, "play #{uuid}")

    case Resolver.resolve(uuid) do
      {:ok, play_params} -> Manager.play(play_params)
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Private Helpers ---

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
      |> EpisodeList.sort_seasons()
      |> Enum.map(fn season ->
        %{season | episodes: EpisodeList.sort_episodes(season.episodes || [])}
      end)

    movies = MovieList.sort_movies(entity.movies || [])

    %{entity | seasons: seasons, movies: movies}
  end
end
