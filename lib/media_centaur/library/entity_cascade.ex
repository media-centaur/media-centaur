defmodule MediaCentaur.Library.EntityCascade do
  @moduledoc """
  FK-safe entity destruction. Deletes a type-specific record and all its
  children (watch progress, extras, seasons/episodes, movies, images,
  identifiers) in the correct order to avoid foreign key violations.

  Does NOT delete WatchedFiles — the caller handles those per use case
  (FileEventHandler deletes them; Rematch converts them to PendingFiles first).
  """
  require MediaCentaur.Log, as: Log
  import Ecto.Query

  alias MediaCentaur.{Config, Format, Repo}
  alias MediaCentaur.Library
  alias MediaCentaur.Library.{ChangeLog, Image, TypeResolver}

  @doc """
  Destroys a type-specific record and all its children in FK-safe order.

  Resolves the UUID to a TVSeries, MovieSeries, Movie, or VideoObject,
  loads full associations, then deletes children in FK-safe order.
  """
  def destroy!(entity_id) do
    {record, entity_type} = resolve_entity!(entity_id)
    ChangeLog.record_removal(record, entity_type)

    destroy_children!(record, entity_type)
    destroy_record!(record, entity_type)

    Log.info(
      :library,
      "cascade-deleted #{entity_type} \"#{record.name}\" (#{Format.short_id(entity_id)})"
    )
  end

  defp resolve_entity!(id) do
    case TypeResolver.resolve(id,
           standalone_movie: false,
           preload: [
             tv_series: Library.tv_series_full_preloads(),
             movie_series: Library.movie_series_full_preloads(),
             movie: Library.movie_full_preloads(),
             video_object: Library.video_object_full_preloads()
           ]
         ) do
      {:ok, type, record} -> {record, type}
      :not_found -> raise "entity #{id} not found in any type-specific table"
    end
  end

  defp destroy_children!(record, :tv_series) do
    Enum.each(record.seasons || [], fn season ->
      episodes = season.episodes || []

      Enum.each(episodes, fn episode ->
        destroy_progress(episode)
        delete_images(episode.images || [])
      end)

      bulk_destroy(episodes, Library.Episode)
      bulk_destroy(season.extras || [], Library.Extra)
      Library.destroy_season!(season)
    end)

    bulk_destroy(record.extras || [], Library.Extra)
    delete_images(record.images || [])
    delete_image_dirs(record)
    bulk_destroy(record.identifiers || [], Library.Identifier)
  end

  defp destroy_children!(record, :movie_series) do
    movies = record.movies || []

    Enum.each(movies, fn movie ->
      destroy_progress(movie)
      delete_images(movie.images || [])
    end)

    bulk_destroy(movies, Library.Movie)
    bulk_destroy(record.extras || [], Library.Extra)
    delete_images(record.images || [])
    delete_image_dirs(record)
    bulk_destroy(record.identifiers || [], Library.Identifier)
  end

  defp destroy_children!(record, :movie) do
    destroy_progress(record)
    bulk_destroy(record.extras || [], Library.Extra)
    delete_images(record.images || [])
    delete_image_dirs(record)
    bulk_destroy(record.identifiers || [], Library.Identifier)
  end

  defp destroy_children!(record, :video_object) do
    destroy_progress(record)
    delete_images(record.images || [])
    delete_image_dirs(record)
    bulk_destroy(record.identifiers || [], Library.Identifier)
  end

  defp destroy_record!(record, :tv_series), do: Library.destroy_tv_series!(record)
  defp destroy_record!(record, :movie_series), do: Library.destroy_movie_series!(record)
  defp destroy_record!(record, :movie), do: Library.destroy_movie!(record)
  defp destroy_record!(record, :video_object), do: Library.destroy_video_object!(record)

  defp destroy_progress(%{watch_progress: nil}), do: :ok
  defp destroy_progress(%{watch_progress: %Ecto.Association.NotLoaded{}}), do: :ok
  defp destroy_progress(%{watch_progress: progress}), do: Library.destroy_watch_progress!(progress)

  @doc false
  def bulk_destroy([], _schema), do: :ok

  def bulk_destroy(records, schema) do
    ids = Enum.map(records, & &1.id)
    from(r in schema, where: r.id in ^ids) |> Repo.delete_all()
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

  defp delete_image_dirs(record) do
    watch_dirs = Config.get(:watch_dirs) || []

    uuids =
      [record.id] ++
        Enum.map(Map.get(record, :movies, []), & &1.id) ++
        Enum.flat_map(Map.get(record, :seasons, []), fn season ->
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
