defmodule MediaCentarr.Maintenance do
  use Boundary,
    deps: [MediaCentarr.Library, MediaCentarr.Pipeline, MediaCentarr.TMDB, MediaCentarr.Watcher]

  @moduledoc """
  Operator-driven destructive operations — Settings → Danger Zone and the
  library-maintenance buttons. These actions intentionally cross context
  boundaries (purge Library schemas, clear image cache, repair missing
  images) so they are owned here rather than in `Settings`, which is
  defined as shared key/value infrastructure with no domain logic.

  See [ADR-029](../decisions/architecture/2026-03-26-029-data-decoupling.md):
  Settings is intentionally one-directional. Cross-context orchestration
  belongs in a dedicated context, not bolted onto a configuration store.
  """
  import Ecto.Query

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Repo
  alias MediaCentarr.Library
  alias MediaCentarr.Library.Image

  alias MediaCentarr.Library.{
    Episode,
    Extra,
    ExtraProgress,
    ExternalId,
    Movie,
    MovieSeries,
    Season,
    TVSeries,
    VideoObject,
    WatchProgress,
    WatchedFile
  }

  alias MediaCentarr.Review.PendingFile
  alias MediaCentarr.TMDB.{Client, Mapper}

  @doc """
  Destroys all records from every library resource in FK-safe order,
  then clears image files from disk.
  """
  def clear_database do
    MediaCentarr.Watcher.Supervisor.pause_during(fn ->
      Log.info(:library, "clearing database")
      entity_ids = collect_all_entity_ids()

      Enum.each(resources_in_delete_order(), fn schema ->
        Repo.delete_all(schema)
      end)

      watch_dirs = MediaCentarr.Config.get(:watch_dirs) || []

      Enum.each(watch_dirs, fn dir ->
        clear_directory(MediaCentarr.Config.images_dir_for(dir))
      end)

      Library.broadcast_entities_changed(entity_ids)

      Log.info(:library, "database cleared")
      :ok
    end)
  end

  @doc """
  Clears all cached artwork from disk, nulls out `content_url` on every
  Image record, then re-downloads images for all entities.

  Returns `{:ok, count}` where `count` is the number of entities processed.
  """
  def refresh_image_cache do
    Log.info(:library, "refreshing image cache")

    watch_dirs = MediaCentarr.Config.get(:watch_dirs) || []

    Enum.each(watch_dirs, fn dir ->
      clear_directory(MediaCentarr.Config.images_dir_for(dir))
    end)

    now = DateTime.utc_now()
    Repo.update_all(Image, set: [content_url: nil, updated_at: now])

    entities = collect_entities_with_images_and_files()

    Enum.each(entities, fn entity ->
      if watch_dir = first_watch_dir(entity) do
        Phoenix.PubSub.broadcast(
          MediaCentarr.PubSub,
          MediaCentarr.Topics.pipeline_images(),
          {:images_pending, %{entity_id: entity.id, watch_dir: watch_dir}}
        )
      end
    end)

    entity_ids = Enum.map(entities, & &1.id)
    Library.broadcast_entities_changed(entity_ids)

    Log.info(:library, "image cache refreshed — #{length(entities)} entities")
    {:ok, length(entities)}
  end

  @doc """
  Backfills the `cast` field on movies that were imported before the
  field existed. Iterates movies with a non-nil `tmdb_id`, re-fetches
  TMDB metadata for ones with empty `cast`, and updates `cast` in
  place via a focused changeset — no images, watch progress, or files
  are touched.

  Idempotent: subsequent runs skip movies that already have non-empty
  cast. Rate-limited automatically by `MediaCentarr.TMDB.RateLimiter`
  inside `Client.get_movie/1`.

  Returns `{:ok, %{updated: n, skipped: n, failed: n}}`.
  """
  @spec refresh_movie_cast() ::
          {:ok, %{updated: non_neg_integer(), skipped: non_neg_integer(), failed: non_neg_integer()}}
  def refresh_movie_cast do
    Log.info(:library, "refreshing movie cast")

    movies = Repo.all(from m in Movie, where: not is_nil(m.tmdb_id))

    result =
      Enum.reduce(movies, %{updated: 0, skipped: 0, failed: 0}, &process_cast_refresh/2)

    Log.info(
      :library,
      "movie cast refresh — #{result.updated} updated, #{result.skipped} skipped, #{result.failed} failed"
    )

    {:ok, result}
  end

  defp process_cast_refresh(%Movie{cast: cast} = _movie, acc) when cast not in [nil, []] do
    Map.update!(acc, :skipped, &(&1 + 1))
  end

  defp process_cast_refresh(%Movie{} = movie, acc) do
    case Client.get_movie(movie.tmdb_id) do
      {:ok, body} ->
        cast = Mapper.extract_cast(body["credits"])

        movie
        |> Ecto.Changeset.change(cast: cast)
        |> Repo.update()
        |> case do
          {:ok, _} -> Map.update!(acc, :updated, &(&1 + 1))
          {:error, _} -> Map.update!(acc, :failed, &(&1 + 1))
        end

      {:error, reason} ->
        Log.warning(
          :library,
          "cast refresh failed for movie #{movie.id}: #{inspect(reason)}"
        )

        Map.update!(acc, :failed, &(&1 + 1))
    end
  end

  @doc """
  Detects `library_images` rows whose files are absent on disk and
  re-queues each one into `pipeline_image_queue` so the pipeline can
  re-download. Uses the existing stored `source_url` when a queue row
  already exists, or re-queries TMDB to reconstruct one otherwise.

  Non-destructive — does not touch existing files on disk or image rows
  that are present. Returns the per-category counts from
  `MediaCentarr.Pipeline.ImageRepair.repair_all/0`.
  """
  @spec repair_missing_images() ::
          {:ok,
           %{
             enqueued: non_neg_integer(),
             queue_reused: non_neg_integer(),
             queue_rebuilt: non_neg_integer(),
             skipped: non_neg_integer()
           }}
  def repair_missing_images do
    MediaCentarr.Pipeline.ImageRepair.repair_all()
  end

  @doc """
  Returns a summary of image-health state — total rows, missing files
  count, and per-role breakdown. For the UI to display the repair button
  prominence.
  """
  @spec missing_images_summary() :: %{
          total: non_neg_integer(),
          missing: non_neg_integer(),
          by_role: %{String.t() => non_neg_integer()}
        }
  def missing_images_summary do
    MediaCentarr.Library.ImageHealth.summary()
  end

  defp resources_in_delete_order do
    [
      PendingFile,
      ExtraProgress,
      WatchProgress,
      Extra,
      Image,
      Episode,
      ExternalId,
      Movie,
      Season,
      WatchedFile,
      TVSeries,
      MovieSeries,
      VideoObject
    ]
  end

  defp collect_all_entity_ids do
    Repo.all(from(t in TVSeries, select: t.id)) ++
      Repo.all(from(m in MovieSeries, select: m.id)) ++
      Repo.all(from(m in Movie, where: is_nil(m.movie_series_id), select: m.id)) ++
      Repo.all(from(v in VideoObject, select: v.id))
  end

  defp collect_entities_with_images_and_files do
    tv = Repo.preload(Repo.all(TVSeries), [:images, :watched_files])
    ms = Repo.preload(Repo.all(MovieSeries), [:images, :watched_files])

    standalone_movies =
      Repo.preload(Repo.all(from(m in Movie, where: is_nil(m.movie_series_id))), [
        :images,
        :watched_files
      ])

    vo = Repo.preload(Repo.all(VideoObject), [:images, :watched_files])

    tv ++ ms ++ standalone_movies ++ vo
  end

  defp first_watch_dir(entity) do
    case entity.watched_files do
      [first | _] ->
        first.watch_dir

      _ ->
        Log.warning(
          :library,
          "entity #{entity.id} has no watched files, skipping image operation"
        )

        nil
    end
  end

  defp clear_directory(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.each(entries, fn entry ->
          File.rm_rf!(Path.join(dir, entry))
        end)

      {:error, _} ->
        :ok
    end
  end
end
