defmodule MediaCentaur.Library.FileEventHandler do
  @moduledoc """
  Handles file removal events and cleans up library records.

  Two entry points:
  - **PubSub** (`{:files_removed, paths}`): triggered by inotify deletions
    or TTL expiration in `Watcher.FilePresence`. Spawns a task to run the
    cleanup cascade.
  - **Direct** (`delete_file/1`, `delete_folder/2`): called from LiveView
    for user-initiated deletions. Deletes from disk, then runs the same
    cleanup cascade.

  The cleanup cascade groups removed files by entity, deletes matching
  child records (episodes, movies, extras, images), and cascades to full
  entity deletion when no WatchedFiles remain.
  """
  use GenServer
  require MediaCentaur.Log, as: Log
  import Ecto.Query

  alias MediaCentaur.Repo
  alias MediaCentaur.Library
  alias MediaCentaur.Library.{EntityCascade, WatchedFile}
  alias MediaCentaur.Library.Helpers

  import EntityCascade, only: [bulk_destroy: 2, delete_images: 1]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # ---------------------------------------------------------------------------
  # Public API — direct file operations (called from LiveView)
  # ---------------------------------------------------------------------------

  @doc """
  Deletes a single file from disk and cleans up its library records.

  `:enoent` (file already gone) is treated as success — the library cleanup
  still runs to remove DB records.
  """
  @spec delete_file(String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def delete_file(file_path) do
    case File.rm(file_path) do
      :ok ->
        Log.info(:library, "deleted file — #{file_path}")
        cleanup_and_broadcast([file_path])

      {:error, :enoent} ->
        Log.info(:library, "cleaned up records — file already absent: #{file_path}")
        cleanup_and_broadcast([file_path])

      {:error, reason} ->
        Log.warning(:library, "failed to delete file — #{file_path}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Deletes a folder and all its contents from disk, then cleans up library
  records for all WatchedFiles that were under that folder.

  `file_paths` must be collected *before* deletion because `rm -rf` does not
  generate per-file inotify events.
  """
  @spec delete_folder(String.t(), [String.t()]) :: {:ok, [String.t()]} | {:error, any()}
  def delete_folder(folder_path, file_paths) do
    watch_dirs = MediaCentaur.Config.get(:watch_dirs) || []

    if folder_path in watch_dirs do
      Log.warning(:library, "refused to delete watch directory — #{folder_path}")
      {:error, :watch_directory}
    else
      delete_folder_unsafe(folder_path, file_paths)
    end
  end

  # ---------------------------------------------------------------------------
  # Public API — cleanup (called directly in tests, via PubSub in production)
  # ---------------------------------------------------------------------------

  @doc """
  Immediately cleans up all library records associated with the given file paths.
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

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_file_events())
    {:ok, %{}}
  end

  @impl true
  def handle_info({:files_removed, file_paths}, state) do
    Log.info(:library, "processing removal — #{length(file_paths)} files")

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      entity_ids = cleanup_removed_files(file_paths)
      Helpers.broadcast_entities_changed(entity_ids)
    end)

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Cleanup cascade
  # ---------------------------------------------------------------------------

  defp do_cleanup(watched_files, file_paths) do
    file_path_set = MapSet.new(file_paths)

    watched_files
    |> Enum.group_by(&owner_id/1)
    |> Enum.flat_map(fn {entity_id, files} ->
      cleanup_entity_files(entity_id, files, file_path_set)
    end)
    |> Enum.uniq()
  end

  defp owner_id(file) do
    file.tv_series_id || file.movie_series_id || file.movie_id || file.video_object_id
  end

  defp cleanup_entity_files(entity_id, watched_files, removed_paths) do
    removed_file_paths =
      watched_files
      |> Enum.map(& &1.file_path)
      |> MapSet.new()
      |> MapSet.intersection(removed_paths)

    seasons = delete_children_for_paths(entity_id, removed_file_paths)

    # WatchedFile records cleaned up after children to avoid FK violations
    files_to_delete = Enum.filter(watched_files, &MapSet.member?(removed_paths, &1.file_path))

    if files_to_delete != [] do
      ids = Enum.map(files_to_delete, & &1.id)
      from(w in WatchedFile, where: w.id in ^ids) |> Repo.delete_all()
    end

    # Check if entity is now orphaned (no remaining WatchedFiles)
    remaining_files = Library.list_watched_files_by_entity_id(entity_id)

    if remaining_files == [] do
      delete_entity_cascade(entity_id)
    else
      cleanup_empty_seasons(seasons)
    end

    [entity_id]
  end

  defp delete_children_for_paths(entity_id, removed_paths) do
    seasons = Library.list_seasons_by_owner_id(entity_id)

    Enum.each(seasons, fn season ->
      matched_episodes =
        Library.list_episodes_for_season!(season.id, load: [:images])
        |> Enum.filter(&(&1.content_url && MapSet.member?(removed_paths, &1.content_url)))

      Enum.each(matched_episodes, fn episode ->
        delete_images(episode.images || [])
      end)

      bulk_destroy(matched_episodes, Library.Episode)
    end)

    matched_movies =
      Library.list_movies_by_owner_id(entity_id, load: [:images])
      |> Enum.filter(&(&1.content_url && MapSet.member?(removed_paths, &1.content_url)))

    Enum.each(matched_movies, fn movie ->
      delete_images(movie.images || [])
    end)

    bulk_destroy(matched_movies, Library.Movie)

    matched_extras =
      Library.list_extras_by_owner_id(entity_id)
      |> Enum.filter(&(&1.content_url && MapSet.member?(removed_paths, &1.content_url)))

    bulk_destroy(matched_extras, Library.Extra)

    seasons
  end

  defp cleanup_empty_seasons(seasons) do
    Enum.each(seasons, fn season ->
      if Library.list_episodes_for_season!(season.id) == [] do
        bulk_destroy(Library.list_extras_for_season!(season.id), Library.Extra)
        Library.destroy_season!(season)
      end
    end)
  end

  defp delete_entity_cascade(entity_id) do
    if Library.list_watched_files_by_entity_id(entity_id) != [] do
      Log.info(
        :library,
        "skipped cascade — entity #{MediaCentaur.Format.short_id(entity_id)} gained files during cleanup"
      )

      :ok
    else
      EntityCascade.destroy!(entity_id)
    end
  end

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  defp delete_folder_unsafe(folder_path, file_paths) do
    case File.rm_rf(folder_path) do
      {:ok, _removed} ->
        Log.info(:library, "deleted folder — #{folder_path}")
        cleanup_and_broadcast(file_paths)

      {:error, reason, _failed_path} ->
        Log.warning(:library, "failed to delete folder — #{folder_path}: #{reason}")
        {:error, reason}
    end
  end

  defp cleanup_and_broadcast(file_paths) do
    entity_ids = cleanup_removed_files(file_paths)
    Helpers.broadcast_entities_changed(entity_ids)
    {:ok, entity_ids}
  end
end
