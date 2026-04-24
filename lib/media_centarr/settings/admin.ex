defmodule MediaCentarr.Settings.Admin do
  @moduledoc """
  Destructive admin operations for development and testing.

  Provides `clear_database/0` and `refresh_image_cache/0` — used by the
  Settings Danger Zone buttons.
  """
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
    import Ecto.Query

    Repo.all(from(t in TVSeries, select: t.id)) ++
      Repo.all(from(m in MovieSeries, select: m.id)) ++
      Repo.all(from(m in Movie, where: is_nil(m.movie_series_id), select: m.id)) ++
      Repo.all(from(v in VideoObject, select: v.id))
  end

  defp collect_entities_with_images_and_files do
    import Ecto.Query

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
