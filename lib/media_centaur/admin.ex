defmodule MediaCentaur.Admin do
  @moduledoc """
  Destructive admin operations for development and testing.

  Provides `clear_database/0` and `refresh_image_cache/0` — used by the
  developer dashboard Danger Zone buttons. All bulk operations use Ash bulk
  APIs to execute single queries instead of per-record loops.
  """
  require Logger
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{Helpers, Image}

  alias MediaCentaur.Library.{
    Entity,
    Episode,
    Extra,
    Identifier,
    Movie,
    Season,
    WatchProgress,
    WatchedFile
  }

  alias MediaCentaur.Review.PendingFile

  @doc """
  Destroys all records from every library resource in FK-safe order,
  then clears image files from disk.
  """
  def clear_database do
    MediaCentaur.Watcher.Supervisor.pause_during(fn ->
      Log.info(:library, "clearing database")
      entity_ids = Library.list_entities!() |> Enum.map(& &1.id)

      resources_in_delete_order()
      |> Enum.each(fn resource ->
        result =
          Ash.bulk_destroy!(resource, :destroy, %{},
            strategy: :stream,
            return_errors?: true
          )

        if result.error_count > 0 do
          Logger.error("Admin: #{inspect(resource)} had #{result.error_count} destroy errors")
        end
      end)

      watch_dirs = MediaCentaur.Config.get(:watch_dirs) || []

      Enum.each(watch_dirs, fn dir ->
        clear_directory(MediaCentaur.Config.images_dir_for(dir))
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
    end)

    result =
      Ash.bulk_update!(Image, :clear_content_url, %{},
        strategy: :stream,
        return_errors?: true
      )

    if result.error_count > 0 do
      Logger.error("Admin: #{result.error_count} images failed to clear content_url")
    end

    entities = Library.list_entities_with_images!(load: [:watched_files])

    Enum.each(entities, fn entity ->
      if watch_dir = first_watch_dir(entity) do
        Phoenix.PubSub.broadcast(
          MediaCentaur.PubSub,
          "pipeline:images",
          {:images_pending, %{entity_id: entity.id, watch_dir: watch_dir}}
        )
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

    incomplete = Library.list_incomplete_images!()

    entity_ids = Helpers.unique_entity_ids(incomplete)

    entities =
      Library.list_entities_with_images!(
        query: [filter: [id: [in: entity_ids]]],
        load: [:watched_files]
      )

    Enum.each(entities, fn entity ->
      if watch_dir = first_watch_dir(entity) do
        Phoenix.PubSub.broadcast(
          MediaCentaur.PubSub,
          "pipeline:images",
          {:images_pending, %{entity_id: entity.id, watch_dir: watch_dir}}
        )
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

    incomplete = Library.list_incomplete_images!()
    entity_ids = Helpers.unique_entity_ids(incomplete)
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
