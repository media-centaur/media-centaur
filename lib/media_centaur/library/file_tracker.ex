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
  alias MediaCentaur.Library.{Entity, Episode, Extra, Helpers, Image, Movie, Season, WatchedFile}

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
    watched_files =
      WatchedFile
      |> Ash.Query.for_read(:by_file_paths, %{file_paths: file_paths})
      |> Ash.read!()

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

    absent_files =
      WatchedFile
      |> Ash.Query.for_read(:by_watch_dir, %{watch_dir: watch_dir, state: :absent})
      |> Ash.read!()

    restored =
      Enum.filter(absent_files, fn file ->
        MapSet.member?(existing_set, file.file_path)
      end)

    if restored != [] do
      Log.info(:library, "restoring #{length(restored)} absent files for #{watch_dir}")

      Enum.each(restored, fn file ->
        file
        |> Ash.Changeset.for_update(:mark_present, %{})
        |> Ash.update!()
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
    files =
      WatchedFile
      |> Ash.Query.for_read(:by_watch_dir, %{watch_dir: watch_dir, state: :complete})
      |> Ash.read!()

    if files == [] do
      []
    else
      Enum.each(files, fn file ->
        file
        |> Ash.Changeset.for_update(:mark_absent, %{})
        |> Ash.update!()
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
        Ash.destroy!(file)
      end
    end)

    # Check if entity is now orphaned (no remaining WatchedFiles)
    remaining_files =
      WatchedFile
      |> Ash.Query.do_filter(%{entity_id: entity_id})
      |> Ash.read!()

    if remaining_files == [] do
      delete_entity_cascade(entity_id)
    else
      cleanup_empty_seasons(entity_id)
    end

    [entity_id]
  end

  defp delete_children_for_paths(entity_id, removed_paths) do
    # Delete episodes whose content_url matches a removed path
    episodes =
      Episode
      |> Ash.read!()
      |> Enum.filter(fn ep ->
        ep.content_url && MapSet.member?(removed_paths, ep.content_url) &&
          episode_belongs_to_entity?(ep, entity_id)
      end)

    Enum.each(episodes, fn episode ->
      delete_episode_images(episode.id)
      Ash.destroy!(episode)
    end)

    # Delete child movies whose content_url matches
    movies =
      Movie
      |> Ash.read!()
      |> Enum.filter(fn movie ->
        movie.entity_id == entity_id && movie.content_url &&
          MapSet.member?(removed_paths, movie.content_url)
      end)

    Enum.each(movies, fn movie ->
      delete_movie_images(movie.id)
      Ash.destroy!(movie)
    end)

    # Delete extras whose content_url matches
    extras =
      Extra
      |> Ash.read!()
      |> Enum.filter(fn extra ->
        extra.entity_id == entity_id && extra.content_url &&
          MapSet.member?(removed_paths, extra.content_url)
      end)

    Enum.each(extras, &Ash.destroy!/1)
  end

  defp episode_belongs_to_entity?(episode, entity_id) do
    season = Ash.get!(Season, episode.season_id)
    season.entity_id == entity_id
  end

  defp cleanup_empty_seasons(entity_id) do
    seasons =
      Season
      |> Ash.read!()
      |> Enum.filter(&(&1.entity_id == entity_id))

    Enum.each(seasons, fn season ->
      episodes =
        Episode
        |> Ash.Query.do_filter(%{season_id: season.id})
        |> Ash.read!()

      if episodes == [] do
        # Also remove any season extras
        extras =
          Extra
          |> Ash.Query.do_filter(%{season_id: season.id})
          |> Ash.read!()

        Enum.each(extras, &Ash.destroy!/1)
        Ash.destroy!(season)
      end
    end)
  end

  defp delete_entity_cascade(entity_id) do
    entity = Ash.get!(Entity, entity_id, action: :with_associations)

    # Delete in FK-safe order
    Enum.each(entity.watch_progress || [], &Ash.destroy!/1)

    Enum.each(entity.extras || [], &Ash.destroy!/1)

    Enum.each(entity.seasons || [], fn season ->
      Enum.each(season.episodes || [], fn episode ->
        delete_episode_images(episode.id)
        Ash.destroy!(episode)
      end)

      Enum.each(season.extras || [], &Ash.destroy!/1)
      Ash.destroy!(season)
    end)

    Enum.each(entity.movies || [], fn movie ->
      delete_movie_images(movie.id)
      Ash.destroy!(movie)
    end)

    delete_entity_images(entity_id)
    delete_image_dirs(entity)

    Enum.each(entity.identifiers || [], &Ash.destroy!/1)

    Ash.destroy!(entity)
    Log.info(:library, "deleted orphaned entity #{entity_id}")
  end

  defp delete_episode_images(episode_id) do
    Image
    |> Ash.read!()
    |> Enum.filter(&(&1.episode_id == episode_id))
    |> Enum.each(fn image ->
      delete_image_file(image)
      Ash.destroy!(image)
    end)
  end

  defp delete_movie_images(movie_id) do
    Image
    |> Ash.read!()
    |> Enum.filter(&(&1.movie_id == movie_id))
    |> Enum.each(fn image ->
      delete_image_file(image)
      Ash.destroy!(image)
    end)
  end

  defp delete_entity_images(entity_id) do
    Image
    |> Ash.read!()
    |> Enum.filter(&(&1.entity_id == entity_id))
    |> Enum.each(fn image ->
      delete_image_file(image)
      Ash.destroy!(image)
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

    expired =
      WatchedFile
      |> Ash.Query.for_read(:expired_absent, %{cutoff: cutoff})
      |> Ash.read!()

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
