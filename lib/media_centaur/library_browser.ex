defmodule MediaCentaur.LibraryBrowser do
  @moduledoc """
  Data-fetching module for the library browser LiveView.
  Keeps the LiveView thin by centralizing all library queries and playback actions.
  """
  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library.Entity
  alias MediaCentaur.Playback.{EpisodeList, MovieList, ProgressSummary, Resolver, Sessions}
  alias MediaCentaur.Repo

  @full_preloads [
    :images,
    :identifiers,
    :watch_progress,
    :extras,
    :extra_progress,
    seasons: [:extras, episodes: :images],
    movies: :images
  ]

  @doc """
  Loads all entities with associations, computes progress summaries.

  Returns a list of `%{entity: entity, progress: summary, progress_records: records}`.
  """
  def fetch_entities do
    entities =
      Entity
      |> with_present_files()
      |> order_by(asc: :name)
      |> Repo.all()
      |> Repo.preload(@full_preloads)

    Log.info(:library, "loaded #{length(entities)} entities for browser")

    Enum.map(entities, &build_entry/1)
  end

  @doc """
  Loads specific entities by ID with full associations and progress.

  Returns `{updated_entries, gone_ids}` where `gone_ids` contains entity IDs
  that no longer exist or have all files absent.
  """
  def fetch_entries_by_ids(entity_ids) do
    entities =
      from(e in Entity, where: e.id in ^entity_ids)
      |> with_present_files()
      |> Repo.all()
      |> Repo.preload(@full_preloads)

    present_ids = MapSet.new(entities, & &1.id)
    requested = MapSet.new(entity_ids)
    gone_ids = MapSet.difference(requested, present_ids)

    entries = Enum.map(entities, &build_entry/1)

    {entries, gone_ids}
  end

  @doc """
  Smart play for any UUID — resolves the target and starts playback.
  """
  def play(uuid) do
    Log.info(:library, "play requested — #{Format.short_id(uuid)}")

    case Resolver.resolve(uuid) do
      {:ok, play_params} -> Sessions.play(play_params)
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Private Helpers ---

  defp with_present_files(query) do
    from(e in query,
      where:
        fragment(
          "NOT EXISTS(SELECT 1 FROM library_watched_files WHERE entity_id = ?) OR EXISTS(SELECT 1 FROM library_watched_files WHERE entity_id = ? AND state = 'complete')",
          e.id,
          e.id
        )
    )
  end

  defp build_entry(entity) do
    entity = entity |> pre_sort_children() |> maybe_unwrap_single_movie()

    progress_records =
      Enum.sort_by(entity.watch_progress, &{&1.season_number, &1.episode_number})

    summary = ProgressSummary.compute(entity, progress_records)

    %{entity: entity, progress: summary, progress_records: progress_records}
  end

  defp maybe_unwrap_single_movie(%{type: :movie_series, movies: [movie]} = entity) do
    %{
      entity
      | type: :movie,
        name: movie.name || entity.name,
        date_published: movie.date_published || entity.date_published,
        content_url: movie.content_url,
        movies: []
    }
  end

  defp maybe_unwrap_single_movie(entity), do: entity

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
