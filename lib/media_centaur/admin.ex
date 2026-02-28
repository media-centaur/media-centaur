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

      images_dir = MediaCentaur.Config.get(:media_images_dir)
      if images_dir, do: clear_directory(images_dir)

      if entity_ids != [], do: Helpers.broadcast_entities_changed(entity_ids)

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
    images_dir = MediaCentaur.Config.get(:media_images_dir)

    if images_dir, do: clear_directory(images_dir)

    Ash.bulk_update!(Image, :clear_content_url, %{}, strategy: :stream)

    entities = Ash.read!(Entity, action: :with_images)

    Enum.each(entities, fn entity ->
      ImageDownloader.download_all(entity)
    end)

    entity_ids = Enum.map(entities, & &1.id)
    if entity_ids != [], do: Helpers.broadcast_entities_changed(entity_ids)

    Logger.info("Admin: image cache refreshed for #{length(entities)} entities")
    {:ok, length(entities)}
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
