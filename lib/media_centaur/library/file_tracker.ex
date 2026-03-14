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
  alias MediaCentaur.Library.EntityCascade
  alias MediaCentaur.Library.Helpers

  import EntityCascade, only: [bulk_destroy: 2, delete_images: 1]

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

      result =
        Ash.bulk_update(restored, :mark_present, %{},
          resource: Library.WatchedFile,
          strategy: :stream,
          return_errors?: true
        )

      if result.error_count > 0 do
        Log.warning(:library, "mark_present bulk errors: #{inspect(result.errors)}")
      end
    end

    Helpers.unique_entity_ids(restored)
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
      result =
        Ash.bulk_update(files, :mark_absent, %{},
          resource: Library.WatchedFile,
          strategy: :stream,
          return_errors?: true
        )

      if result.error_count > 0 do
        Log.warning(:library, "mark_absent bulk errors: #{inspect(result.errors)}")
      end

      Helpers.unique_entity_ids(files)
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_file_events())
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.watcher_state())
    schedule_ttl_check()
    {:ok, %{}, {:continue, :initial_ttl_check}}
  end

  @impl true
  def handle_continue(:initial_ttl_check, state) do
    check_ttl_expirations()
    {:noreply, state}
  end

  @impl true
  def handle_info({:files_removed, file_paths}, state) do
    Log.info(:library, "processing removal of #{length(file_paths)} files")

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      entity_ids = cleanup_removed_files(file_paths)
      Helpers.broadcast_entities_changed(entity_ids)
    end)

    {:noreply, state}
  end

  def handle_info({:watcher_state_changed, dir, :unavailable}, state) do
    Log.info(:library, "drive unavailable, marking files absent for #{dir}")

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      entity_ids = mark_absent_for_watch_dir(dir)
      Helpers.broadcast_entities_changed(entity_ids)
    end)

    {:noreply, state}
  end

  def handle_info({:watcher_state_changed, _dir, _state}, state) do
    {:noreply, state}
  end

  def handle_info(:ttl_check, state) do
    check_ttl_expirations()
    schedule_ttl_check()
    {:noreply, state}
  end

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

    by_entity
    |> Enum.flat_map(fn {entity_id, files} ->
      cleanup_entity_files(entity_id, files, file_path_set)
    end)
    |> Enum.uniq()
  end

  defp cleanup_entity_files(entity_id, watched_files, removed_paths) do
    removed_file_paths =
      watched_files
      |> Enum.map(& &1.file_path)
      |> MapSet.new()
      |> MapSet.intersection(removed_paths)

    delete_children_for_paths(entity_id, removed_file_paths)

    # WatchedFile records cleaned up after children to avoid FK violations
    files_to_delete = Enum.filter(watched_files, &MapSet.member?(removed_paths, &1.file_path))

    if files_to_delete != [] do
      result =
        Ash.bulk_destroy(files_to_delete, :destroy, %{},
          resource: Library.WatchedFile,
          strategy: :stream,
          return_errors?: true
        )

      if result.error_count > 0 do
        Log.warning(:library, "bulk destroy watched files errors: #{inspect(result.errors)}")
      end
    end

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
      matched_episodes =
        Library.list_episodes_for_season!(season.id, load: [:images])
        |> Enum.filter(&(&1.content_url && MapSet.member?(removed_paths, &1.content_url)))

      Enum.each(matched_episodes, fn episode ->
        delete_images(episode.images || [])
      end)

      bulk_destroy(matched_episodes, Library.Episode)
    end)

    # Delete child movies whose content_url matches
    matched_movies =
      Library.list_movies_for_entity!(entity_id, load: [:images])
      |> Enum.filter(&(&1.content_url && MapSet.member?(removed_paths, &1.content_url)))

    Enum.each(matched_movies, fn movie ->
      delete_images(movie.images || [])
    end)

    bulk_destroy(matched_movies, Library.Movie)

    # Delete extras whose content_url matches
    matched_extras =
      Library.list_extras_for_entity!(entity_id)
      |> Enum.filter(&(&1.content_url && MapSet.member?(removed_paths, &1.content_url)))

    bulk_destroy(matched_extras, Library.Extra)
  end

  defp cleanup_empty_seasons(entity_id) do
    Enum.each(Library.list_seasons_for_entity!(entity_id), fn season ->
      if Library.list_episodes_for_season!(season.id) == [] do
        bulk_destroy(Library.list_extras_for_season!(season.id), Library.Extra)
        Library.destroy_season!(season)
      end
    end)
  end

  defp delete_entity_cascade(entity_id) do
    # Re-check for new files before committing to the cascade.
    # A file may have been linked between the caller's check and now.
    if Library.list_watched_files_for_entity!(entity_id) != [] do
      Log.info(:library, "entity #{entity_id} gained files during cleanup, skipping cascade")
      :ok
    else
      do_delete_entity_cascade(entity_id)
    end
  end

  defp do_delete_entity_cascade(entity_id) do
    EntityCascade.destroy!(entity_id)
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
