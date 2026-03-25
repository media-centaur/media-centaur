defmodule MediaCentaur.Library.EntityCascade do
  @moduledoc """
  FK-safe entity destruction. Deletes an entity and all its children
  (watch progress, extras, seasons/episodes, movies, images, identifiers)
  in the correct order to avoid foreign key violations.

  Does NOT delete WatchedFiles — the caller handles those per use case
  (FileTracker deletes them; Rematch converts them to PendingFiles first).
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.{Config, Format}
  alias MediaCentaur.Library
  alias MediaCentaur.Library.{ChangeLog, Image}

  @doc """
  Destroys an entity and all its children in FK-safe order.

  Loads the entity with full associations, then deletes:
  WatchProgress → ExtraProgress → Extras → (Episode images → Episodes → Season extras → Seasons) →
  (Movie images → Movies) → Entity images → Image dirs → Identifiers → Entity
  """
  def destroy!(entity_id) do
    entity = Library.get_entity_with_associations!(entity_id)
    ChangeLog.record_removal(entity)

    bulk_destroy(entity.watch_progress || [], Library.WatchProgress)
    bulk_destroy(entity.extra_progress || [], Library.ExtraProgress)

    bulk_destroy(entity.extras || [], Library.Extra)

    Enum.each(entity.seasons || [], fn season ->
      episodes = season.episodes || []

      Enum.each(episodes, fn episode ->
        delete_images(episode.images || [])
      end)

      bulk_destroy(episodes, Library.Episode)
      bulk_destroy(season.extras || [], Library.Extra)
      Library.destroy_season!(season)
    end)

    movies = entity.movies || []

    Enum.each(movies, fn movie ->
      delete_images(movie.images || [])
    end)

    bulk_destroy(movies, Library.Movie)

    delete_images(entity.images || [])
    delete_image_dirs(entity)

    bulk_destroy(entity.identifiers || [], Library.Identifier)

    Library.destroy_entity!(entity)

    Log.info(
      :library,
      "cascade-deleted #{entity.type} \"#{entity.name}\" (#{Format.short_id(entity_id)})"
    )
  end

  @doc false
  def bulk_destroy([], _resource), do: :ok

  def bulk_destroy(records, resource) do
    result =
      Ash.bulk_destroy(records, :destroy, %{},
        resource: resource,
        strategy: :stream,
        return_errors?: true
      )

    if result.error_count > 0 do
      Log.warning(
        :library,
        "bulk destroy failed — #{inspect(resource)}: #{inspect(result.errors)}"
      )
    end
  end

  @doc false
  def delete_images([]), do: :ok

  def delete_images(images) do
    Enum.each(images, &delete_image_file/1)
    bulk_destroy(images, Image)
  end

  defp delete_image_file(%Image{content_url: nil}), do: :ok

  defp delete_image_file(%Image{content_url: content_url}) do
    case Config.resolve_image_path(content_url) do
      nil -> :ok
      path -> File.rm(path)
    end
  end

  defp delete_image_dirs(entity) do
    watch_dirs = Config.get(:watch_dirs) || []

    uuids =
      [entity.id] ++
        Enum.map(entity.movies || [], & &1.id) ++
        Enum.flat_map(entity.seasons || [], fn season ->
          Enum.map(season.episodes || [], & &1.id)
        end)

    Enum.each(watch_dirs, fn dir ->
      images_dir = Config.images_dir_for(dir)

      Enum.each(uuids, fn uuid ->
        uuid_dir = Path.join(images_dir, uuid)

        if File.dir?(uuid_dir) do
          File.rm_rf(uuid_dir)
        end
      end)
    end)
  end
end
