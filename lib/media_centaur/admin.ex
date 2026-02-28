defmodule MediaCentaur.Admin do
  @moduledoc """
  Destructive admin operations for development and testing.

  Provides `clear_database/0` and `refresh_image_cache/0` — used by the
  developer dashboard Danger Zone buttons. All bulk operations use Ash bulk
  APIs to execute single queries instead of per-record loops.
  """
  require Logger
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library.{
    Entity,
    Episode,
    Extra,
    Helpers,
    Identifier,
    Image,
    Movie,
    Season,
    WatchProgress,
    WatchedFile
  }

  alias MediaCentaur.Review.PendingFile

  alias MediaCentaur.Pipeline.ImageDownloader

  @doc """
  Destroys all records from every library resource in FK-safe order,
  then clears image files from disk.
  """
  def clear_database do
    MediaCentaur.Watcher.Supervisor.pause_during(fn ->
      Log.info(:library, "clearing database")
      entity_ids = Ash.read!(Entity, action: :read) |> Enum.map(& &1.id)

      resources_in_delete_order()
      |> Enum.each(fn resource ->
        Ash.bulk_destroy!(resource, :destroy, %{}, strategy: :stream)
      end)

      watch_dirs = MediaCentaur.Config.get(:watch_dirs) || []

      Enum.each(watch_dirs, fn dir ->
        clear_directory(MediaCentaur.Config.images_dir_for(dir))
        cleanup_staging_for(dir)
      end)

      Helpers.broadcast_entities_changed(entity_ids)

      Logger.info("Admin: database cleared")
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

    watch_dirs = MediaCentaur.Config.get(:watch_dirs) || []

    Enum.each(watch_dirs, fn dir ->
      clear_directory(MediaCentaur.Config.images_dir_for(dir))
      cleanup_staging_for(dir)
    end)

    Ash.bulk_update!(Image, :clear_content_url, %{}, strategy: :stream)

    entities = Ash.read!(Entity, action: :with_images, load: [:watched_files])

    Enum.each(entities, fn entity ->
      if watch_dir = first_watch_dir(entity) do
        ImageDownloader.download_all(entity, watch_dir)
      end
    end)

    entity_ids = Enum.map(entities, & &1.id)
    Helpers.broadcast_entities_changed(entity_ids)

    Logger.info("Admin: image cache refreshed for #{length(entities)} entities")
    {:ok, length(entities)}
  end

  @doc """
  Re-downloads all images that have a TMDB URL but no local content.

  Groups incomplete images by parent entity and calls the image downloader
  for each. Returns `{:ok, %{retried: count}}`.
  """
  def retry_incomplete_images do
    Log.info(:library, "retrying incomplete images")

    incomplete = Ash.read!(Image, action: :incomplete)

    entity_ids =
      incomplete
      |> Enum.map(& &1.entity_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    entities =
      Enum.map(entity_ids, fn id ->
        Ash.get!(Entity, id, action: :with_images, load: [:watched_files])
      end)

    Enum.each(entities, fn entity ->
      if watch_dir = first_watch_dir(entity) do
        ImageDownloader.download_all(entity, watch_dir)
      end
    end)

    Helpers.broadcast_entities_changed(entity_ids)

    Logger.info("Admin: retried incomplete images for #{length(entities)} entities")
    {:ok, %{retried: length(incomplete)}}
  end

  @doc """
  Deletes all Image records that have a TMDB URL but no local content.

  These are records pointing to remote URLs that were never successfully
  downloaded. Returns `{:ok, count}`.
  """
  def dismiss_incomplete_images do
    Log.info(:library, "dismissing incomplete images")

    incomplete = Ash.read!(Image, action: :incomplete)
    entity_ids = incomplete |> Enum.map(& &1.entity_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    count = length(incomplete)

    Ash.bulk_destroy!(incomplete, :destroy, %{}, strategy: :stream, return_errors?: true)

    Helpers.broadcast_entities_changed(entity_ids)

    Logger.info("Admin: dismissed #{count} incomplete images")
    {:ok, count}
  end

  defp resources_in_delete_order do
    [
      PendingFile,
      WatchProgress,
      Extra,
      Image,
      Episode,
      Identifier,
      Movie,
      Season,
      WatchedFile,
      Entity
    ]
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

  defp cleanup_staging_for(dir) do
    File.rm_rf(MediaCentaur.Config.staging_base_for(dir))
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
