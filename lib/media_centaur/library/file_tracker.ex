defmodule MediaCentaur.Library.FileTracker do
  @moduledoc """
  Tracks file presence and cleans up library records when media files are
  removed or drives become unavailable.

  Two cleanup paths:
  - **Immediate** (`cleanup_removed_files/1`): for confirmed file deletions
    detected by inotify. Deletes WatchedFiles, child records, empty parents,
    and cached images.
  - **Deferred** (`mark_absent_for_watch_dir/1`): for drive unavailability.
    Marks files as absent; a periodic TTL check later runs the same cleanup.

  Subscribes to PubSub for file removal events and watcher state changes.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Config
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Helpers
  alias MediaCentaur.Library.Image

  @ttl_check_interval :timer.hours(24)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # ---------------------------------------------------------------------------
  # Public API (called directly in tests, via PubSub in production)
  # ---------------------------------------------------------------------------

  @doc """
  Immediately cleans up all records associated with the given file paths.
  Returns a list of affected entity IDs (for broadcasting).
  """
  @spec cleanup_removed_files([String.t()]) :: [String.t()]
  def cleanup_removed_files([]), do: []

  def cleanup_removed_files(file_paths) do
    watched_files = Library.list_files_by_paths!(file_paths)

    if watched_files == [] do
      []
    else
      do_cleanup(watched_files, file_paths)
    end
  end

  @doc """
  Restores absent WatchedFiles whose file paths appear in `existing_paths`.
  Marks them as `:complete` and clears `absent_since`.
  Returns a list of affected entity IDs (for broadcasting).
  """
  @spec restore_present_files(String.t(), [String.t()]) :: [String.t()]
  def restore_present_files(_watch_dir, []), do: []

  def restore_present_files(watch_dir, existing_paths) do
    existing_set = MapSet.new(existing_paths)

    absent_files = Library.list_files_by_watch_dir!(watch_dir, :absent)

    restored =
      Enum.filter(absent_files, fn file ->
        MapSet.member?(existing_set, file.file_path)
      end)

    if restored != [] do
      Log.info(:library, "restoring #{length(restored)} absent files for #{watch_dir}")

      Enum.each(restored, fn file ->
        Library.mark_file_present!(file)
      end)
    end

    restored
    |> Enum.map(& &1.entity_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc """
  Marks all complete WatchedFiles for the given watch directory as absent.
  Returns a list of affected entity IDs (for broadcasting).
  """
  @spec mark_absent_for_watch_dir(String.t()) :: [String.t()]
  def mark_absent_for_watch_dir(watch_dir) do
    files = Library.list_files_by_watch_dir!(watch_dir, :complete)

    if files == [] do
      []
    else
      Enum.each(files, fn file ->
        Library.mark_file_absent!(file)
      end)

      files
      |> Enum.map(& &1.entity_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:file_events")
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "watcher:state")
    schedule_ttl_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:files_removed, file_paths}, state) do
    Log.info(:library, "processing removal of #{length(file_paths)} files")
    entity_ids = cleanup_removed_files(file_paths)
    Helpers.broadcast_entities_changed(entity_ids)
    {:noreply, state}
  end

  @impl true
  def handle_info({:watcher_state_changed, dir, :unavailable}, state) do
    Log.info(:library, "drive unavailable, marking files absent for #{dir}")
    entity_ids = mark_absent_for_watch_dir(dir)
    Helpers.broadcast_entities_changed(entity_ids)
    {:noreply, state}
  end

  @impl true
  def handle_info({:watcher_state_changed, _dir, _state}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:ttl_check, state) do
    check_ttl_expirations()
    schedule_ttl_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Cleanup cascade
  # ---------------------------------------------------------------------------

  defp do_cleanup(watched_files, file_paths) do
    file_path_set = MapSet.new(file_paths)

    # Group by entity
    by_entity =
      watched_files
      |> Enum.group_by(& &1.entity_id)

    entity_ids =
      Enum.flat_map(by_entity, fn {entity_id, files} ->
        cleanup_entity_files(entity_id, files, file_path_set)
      end)
      |> Enum.uniq()

    entity_ids
  end

  defp cleanup_entity_files(entity_id, watched_files, removed_paths) do
    removed_file_paths =
      watched_files
      |> Enum.map(& &1.file_path)
      |> MapSet.new()
      |> MapSet.intersection(removed_paths)

    # Delete child records matching removed file paths
    delete_children_for_paths(entity_id, removed_file_paths)

    # Delete the WatchedFile records
    Enum.each(watched_files, fn file ->
      if MapSet.member?(removed_paths, file.file_path) do
        Library.destroy_watched_file!(file)
      end
    end)

    # Check if entity is now orphaned (no remaining WatchedFiles)
    remaining_files = Library.list_watched_files_for_entity!(entity_id)

    if remaining_files == [] do
      delete_entity_cascade(entity_id)
    else
      cleanup_empty_seasons(entity_id)
    end

    [entity_id]
  end

  defp delete_children_for_paths(entity_id, removed_paths) do
    # Delete episodes whose content_url matches a removed path
    Library.list_seasons_for_entity!(entity_id)
    |> Enum.each(fn season ->
      Library.list_episodes_for_season!(season.id)
      |> Enum.filter(&(&1.content_url && MapSet.member?(removed_paths, &1.content_url)))
      |> Enum.each(fn episode ->
        delete_images(Library.list_images_for_episode!(episode.id))
        Library.destroy_episode!(episode)
      end)
    end)

    # Delete child movies whose content_url matches
    Library.list_movies_for_entity!(entity_id)
    |> Enum.filter(&(&1.content_url && MapSet.member?(removed_paths, &1.content_url)))
    |> Enum.each(fn movie ->
      delete_images(Library.list_images_for_movie!(movie.id))
      Library.destroy_movie!(movie)
    end)

    # Delete extras whose content_url matches
    Library.list_extras_for_entity!(entity_id)
    |> Enum.filter(&(&1.content_url && MapSet.member?(removed_paths, &1.content_url)))
    |> Enum.each(&Library.destroy_extra!/1)
  end

  defp cleanup_empty_seasons(entity_id) do
    Enum.each(Library.list_seasons_for_entity!(entity_id), fn season ->
      if Library.list_episodes_for_season!(season.id) == [] do
        Enum.each(Library.list_extras_for_season!(season.id), &Library.destroy_extra!/1)
        Library.destroy_season!(season)
      end
    end)
  end

  defp delete_entity_cascade(entity_id) do
    entity = Library.get_entity_with_associations!(entity_id)

    # Delete in FK-safe order
    Enum.each(entity.watch_progress || [], &Library.destroy_watch_progress!/1)

    Enum.each(entity.extras || [], &Library.destroy_extra!/1)

    Enum.each(entity.seasons || [], fn season ->
      Enum.each(season.episodes || [], fn episode ->
        delete_images(Library.list_images_for_episode!(episode.id))
        Library.destroy_episode!(episode)
      end)

      Enum.each(season.extras || [], &Library.destroy_extra!/1)
      Library.destroy_season!(season)
    end)

    Enum.each(entity.movies || [], fn movie ->
      delete_images(Library.list_images_for_movie!(movie.id))
      Library.destroy_movie!(movie)
    end)

    delete_images(Library.list_images_for_entity!(entity_id))
    delete_image_dirs(entity)

    Enum.each(entity.identifiers || [], &Library.destroy_identifier!/1)

    Library.destroy_entity!(entity)
    Log.info(:library, "deleted orphaned entity #{entity_id}")
  end

  defp delete_images(images) do
    Enum.each(images, fn image ->
      delete_image_file(image)
      Library.destroy_image!(image)
    end)
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

  # ---------------------------------------------------------------------------
  # TTL expiration
  # ---------------------------------------------------------------------------

  defp check_ttl_expirations do
    ttl_days = Config.get(:file_absence_ttl_days) || 30
    cutoff = DateTime.add(DateTime.utc_now(), -ttl_days, :day)

    expired = Library.list_expired_absent_files!(cutoff)

    if expired != [] do
      Log.info(:library, "TTL expiration: cleaning up #{length(expired)} absent files")
      file_paths = Enum.map(expired, & &1.file_path)
      entity_ids = cleanup_removed_files(file_paths)
      Helpers.broadcast_entities_changed(entity_ids)
    end
  end

  defp schedule_ttl_check do
    Process.send_after(self(), :ttl_check, @ttl_check_interval)
  end
end
