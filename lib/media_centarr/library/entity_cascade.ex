defmodule MediaCentarr.Library.EntityCascade do
  @moduledoc """
  FK-safe container destruction. Deletes a `TVSeries`, `MovieSeries`,
  `Movie`, or `VideoObject` and all its children in the correct order.

  ## Cascade order

  Library Schema v2 Phase 2 unified the supporting-row cleanup around the
  `(owner_type, owner_id)` polymorphic discriminator (Tasks D/E/F) and the
  `PlayableItem` leaf identity (Tasks A–C, G). The cascade now has one
  uniform shape per container:

      1. Walk the container's children (seasons → episodes, or child movies).
         For each leaf (Episode / child Movie / standalone Movie / VideoObject):
           a. Delete the leaf's PlayableItem rows by `(container_type, container_id)`.
              WatchedFiles and WatchProgress cascade automatically via their
              `on_delete: :delete_all` FK to `library_playable_items`.
           b. Delete the leaf's polymorphic supporting rows
              (Image / Extra / ExternalId) by `(owner_type, owner_id)`.
           c. Delete the leaf container row itself.
      2. Delete the parent container's own polymorphic supporting rows
         (Image / Extra / ExternalId by `(owner_type, owner_id)`, plus the
         Season's Extras for TV series).
      3. Remove every image-file directory under each watch dir's images_dir
         that matches a UUID belonging to this container or its leaves.
      4. Delete the container row.

  ## What this module DOES NOT delete

    * `WatchedFile` rows — caller-owned. `FileEventHandler` deletes them
      directly when the watcher reports the file gone; `Rematch` converts
      them to PendingFiles before invoking the cascade so the user can
      re-link them.

  Cascade of WatchedFile/WatchProgress through the PlayableItem deletion
  is a DB-level effect (FK `on_delete: :delete_all`), not an Ecto-level
  one — there are no `Repo.delete` calls for those rows, so no
  per-row broadcasts fire. Callers that depend on per-row deletion
  signals should reload after `destroy!/1` returns.
  """
  require MediaCentarr.Log, as: Log
  import Ecto.Query

  alias MediaCentarr.{Config, Format, Repo}
  alias MediaCentarr.Library
  alias MediaCentarr.Library.{ChangeLog, Extra, ExternalId, Image, PlayableItem, TypeResolver}

  @doc """
  Destroys a container UUID and its full subtree of children + supporting
  rows + on-disk image files. See module docs for ordering.

  Raises if the UUID does not resolve to a `TVSeries`, `MovieSeries`,
  standalone `Movie`, or `VideoObject` — orphan UUIDs are a programming
  error at this seam, not a runtime condition the caller is expected to
  handle.
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
    case TypeResolver.resolve_container(id,
           standalone_movie: false,
           preload: Library.full_preloads_by_type()
         ) do
      {:ok, type, record} -> {record, type}
      :not_found -> raise "entity #{id} not found in any type-specific table"
    end
  end

  # ---------------------------------------------------------------------------
  # Per-type entry points — each container type owns a different child shape
  # (TVSeries → Seasons → Episodes; MovieSeries → Movies; Movie/VideoObject
  # → leaves only), but the supporting-row cleanup is uniform.
  # ---------------------------------------------------------------------------

  defp destroy_children!(record, :tv_series) do
    Enum.each(record.seasons || [], fn season ->
      Enum.each(season.episodes || [], &destroy_leaf!(&1, :episode))
      bulk_destroy(season.episodes || [], Library.Episode)
      delete_polymorphic(Extra, :season, season.id)
      Library.destroy_season!(season)
    end)

    destroy_supporting_rows!(record, :tv_series)
    delete_image_dirs(record)
  end

  defp destroy_children!(record, :movie_series) do
    Enum.each(record.movies || [], &destroy_leaf!(&1, :movie))
    bulk_destroy(record.movies || [], Library.Movie)

    destroy_supporting_rows!(record, :movie_series)
    delete_image_dirs(record)
  end

  defp destroy_children!(record, :movie) do
    destroy_leaf!(record, :movie)
    delete_image_dirs(record)
  end

  defp destroy_children!(record, :video_object) do
    destroy_leaf!(record, :video_object)
    delete_image_dirs(record)
  end

  defp destroy_record!(record, :tv_series), do: Library.destroy_tv_series!(record)
  defp destroy_record!(record, :movie_series), do: Library.destroy_movie_series!(record)
  defp destroy_record!(record, :movie), do: Library.destroy_movie!(record)
  defp destroy_record!(record, :video_object), do: Library.destroy_video_object!(record)

  # ---------------------------------------------------------------------------
  # Uniform polymorphic cleanup
  # ---------------------------------------------------------------------------

  # Drops every PlayableItem + supporting row that belongs to a single leaf
  # (Episode / Movie / VideoObject — the container types that own
  # PlayableItems). Library Schema v2 Phase 2 Task G made PlayableItem the
  # canonical leaf, so it must come down with the container.
  #
  # Order: supporting rows first (including the preloaded WatchProgress
  # struct via `destroy_progress/1`), then PlayableItem rows. Dropping
  # PlayableItem first would cascade-delete WatchProgress via the
  # `on_delete: :delete_all` FK, leaving `destroy_progress/1` with a
  # stale struct that raises `Ecto.StaleEntryError` on the explicit
  # `Repo.delete`.
  defp destroy_leaf!(record, leaf_type) when leaf_type in [:movie, :episode, :video_object] do
    destroy_supporting_rows!(record, leaf_type)
    delete_playable_items(leaf_type, record.id)
  end

  # Deletes the polymorphic supporting rows (Image / Extra / ExternalId)
  # for `(owner_type, record.id)`. Images use the preloaded `:images`
  # association so on-disk files are removed before the rows. Extras and
  # ExternalIds are deleted by querying on the discriminator pair —
  # uniform across container types and resilient to which preloads the
  # caller arranged.
  #
  # Each supporting schema accepts a different subset of owner types
  # (Image: all five; Extra: only `:movie | :tv_series | :movie_series |
  # :season`; ExternalId: container-only, no `:episode` or `:season`).
  # `delete_polymorphic/3` is a no-op when the schema doesn't accept the
  # owner type so callers can stay uniform across leaf and container.
  defp destroy_supporting_rows!(record, owner_type) do
    destroy_progress(record)
    delete_images(loaded_assoc(record, :images))
    delete_polymorphic(Extra, owner_type, record.id)
    delete_polymorphic(ExternalId, owner_type, record.id)
  end

  defp loaded_assoc(record, key) do
    case Map.get(record, key) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      list when is_list(list) -> list
    end
  end

  defp delete_polymorphic(schema, owner_type, owner_id) do
    if owner_type in schema.owner_types() do
      Repo.delete_all(
        from(r in schema,
          where: r.owner_type == ^owner_type and r.owner_id == ^owner_id
        )
      )
    end

    :ok
  end

  # Drops every `PlayableItem` row pointing at `(container_type,
  # container_id)`. Library Schema v2 Phase 2 Task G hoisted PlayableItem
  # creation alongside the container row, so the cascade has to mirror it
  # on the way out — the `container_id` link has no DB-level FK
  # enforcement (PlayableItem moduledoc — discriminator design), so
  # orphans would otherwise survive a destroy!. Cascading WatchedFile /
  # WatchProgress rows are dropped automatically via their
  # `on_delete: :delete_all` FK to PlayableItem.
  defp delete_playable_items(container_type, container_id) do
    Repo.delete_all(
      from(p in PlayableItem,
        where: p.container_type == ^container_type and p.container_id == ^container_id
      )
    )

    :ok
  end

  @doc false
  def destroy_progress(%{watch_progress: nil}), do: :ok
  def destroy_progress(%{watch_progress: %Ecto.Association.NotLoaded{}}), do: :ok

  def destroy_progress(%{watch_progress: progress}), do: Library.destroy_watch_progress!(progress)

  # Some records (Season, TVSeries) don't have a :watch_progress field.
  def destroy_progress(_record), do: :ok

  @doc false
  def bulk_destroy([], _schema), do: :ok

  def bulk_destroy(records, schema) do
    ids = Enum.map(records, & &1.id)
    Repo.delete_all(from(r in schema, where: r.id in ^ids))
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
