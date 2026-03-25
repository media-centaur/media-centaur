defmodule MediaCentaur.Admin do
  @moduledoc """
  Destructive admin operations for development and testing.

  Provides `clear_database/0` and `refresh_image_cache/0` — used by the
  developer dashboard Danger Zone buttons.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Repo
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

      Enum.each(resources_in_delete_order(), fn schema ->
        Repo.delete_all(schema)
      end)

      watch_dirs = MediaCentaur.Config.get(:watch_dirs) || []

      Enum.each(watch_dirs, fn dir ->
        clear_directory(MediaCentaur.Config.images_dir_for(dir))
      end)

      Helpers.broadcast_entities_changed(entity_ids)

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

    watch_dirs = MediaCentaur.Config.get(:watch_dirs) || []

    Enum.each(watch_dirs, fn dir ->
      clear_directory(MediaCentaur.Config.images_dir_for(dir))
    end)

    now = DateTime.utc_now()
    Repo.update_all(Image, set: [content_url: nil, updated_at: now])

    entities = Library.list_entities_with_images!(load: [:watched_files])

    Enum.each(entities, fn entity ->
      if watch_dir = first_watch_dir(entity) do
        Phoenix.PubSub.broadcast(
          MediaCentaur.PubSub,
          MediaCentaur.Topics.pipeline_images(),
          {:images_pending, %{entity_id: entity.id, watch_dir: watch_dir}}
        )
      end
    end)

    entity_ids = Enum.map(entities, & &1.id)
    Helpers.broadcast_entities_changed(entity_ids)

    Log.info(:library, "image cache refreshed — #{length(entities)} entities")
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
