defmodule MediaCentarr.Watcher do
  use Boundary, deps: [MediaCentarr.Library], exports: [Supervisor, FilePresence]

  @moduledoc """
  Per-directory inotify GenServer plus the watcher subsystem's module-level
  public functions.

  This module wears two hats:

  - **GenServer:** one process per watched directory, registered in
    `MediaCentarr.Watcher.Registry`. Started by `MediaCentarr.Watcher.Supervisor`.
    Per-pid functions (`status/1`, `dir/1`, `scan/1`) are mostly internal —
    callers go through the supervisor's aggregate APIs (`statuses/0`, `scan/0`).

  - **Module-level facade:** stateless entry points that don't need a pid:

      MediaCentarr.Watcher.validate_dir(entry, existing)
      MediaCentarr.Watcher.record_seen(attrs)

    Aggregate operations (subscribe, statuses, scan all dirs, pause_during,
    start/stop, reconcile, image-dir monitors, rescan_unlinked) live on
    `MediaCentarr.Watcher.Supervisor` — the supervisor module is the
    operational facade for "do this across every running watcher".

  ## Event-driven pipeline integration

  Instead of creating database records, the watcher broadcasts PubSub events
  to `MediaCentarr.Topics.pipeline_input()`. The Pipeline Producer subscribes
  to this topic and converts events into Payloads for Broadway processing.

  - `detect_file/2` broadcasts `{:file_detected, %{path, watch_dir}}`
  - scans read existing WatchedFile file_paths to skip already-processed files

  ## Internal helpers

  Pure modules pulled out of this GenServer to keep the file focused on
  inotify-event routing and lifecycle management:

  - `Watcher.DeletionBuffer` — debouncing buffer for deleted-path events
  - `Watcher.Walk` — recursive directory walk with FS adapter
  - `Watcher.MountStatus` — health-check decision logic
  - `Watcher.ExcludeDirs` — precompiled prefix-match filter
  - `Watcher.VideoFile` — canonical video extension list and predicate

  ## Mount Resilience

  Watch directories may reside on removable drives, NAS shares, or external
  mounts. The watcher handles transient mount failures:

  - **Unmount detection:** inotify fires `IN_UNMOUNT` when a watched filesystem
    is ejected. The watcher transitions to `:unavailable` and stops forwarding events.
  - **Health check re-watch:** a periodic check (every 30s) detects when the
    directory becomes accessible again and re-initialises the file system watcher.

  ## State Lifecycle

      :initializing → :watching → :unavailable → :watching
  """
  use GenServer
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Library
  alias MediaCentarr.Library.WatchedFile
  alias MediaCentarr.Topics
  alias MediaCentarr.Watcher.DeletionBuffer
  alias MediaCentarr.Watcher.ExcludeDirs
  alias MediaCentarr.Watcher.FilePresence
  alias MediaCentarr.Watcher.MountStatus
  alias MediaCentarr.Watcher.VideoFile
  alias MediaCentarr.Watcher.Walk

  @health_check_interval 30_000
  @size_stability_interval 5_000
  @size_stability_checks 2
  @deletion_debounce_ms 3_000
  defstruct [
    :dir,
    :watcher_pid,
    :deletion_timer,
    :device_id,
    state: :initializing,
    was_unavailable: false,
    pending_files: %{},
    deletion_buffer: %DeletionBuffer{},
    skip_dirs: [],
    exclude_dirs: %ExcludeDirs.Prepared{entries: []}
  ]

  def start_link(dir) do
    GenServer.start_link(__MODULE__, dir, name: {:via, Registry, {MediaCentarr.Watcher.Registry, dir}})
  end

  def status(pid), do: GenServer.call(pid, :status)
  def dir(pid), do: GenServer.call(pid, :dir)

  @doc """
  Walks the watched directory recursively, detects video files not yet tracked.
  Returns `{:ok, count}` where count is the number of newly detected files.
  """
  def scan(pid), do: GenServer.call(pid, :scan, 60_000)

  @doc """
  Validates a watch-directory form entry against all 11 rules. Returns
  `%{errors: [...], warnings: [...], preview: nil | %{...}}`.

  Thin facade over `MediaCentarr.Watcher.DirValidator` — binds the production
  filesystem adapter so callers don't need to reach into Watcher internals.
  """
  @spec validate_dir(map(), [map()]) :: map()
  def validate_dir(entry, existing_entries) do
    MediaCentarr.Watcher.DirValidator.validate(
      entry,
      existing_entries,
      MediaCentarr.Watcher.DirValidator.real_fs()
    )
  end

  @doc """
  Records a file as seen by the watcher AND linked to a library entity, in
  a single transaction. Used by the showcase seeder and any future caller
  that needs both rows written atomically — historically these were two
  unrelated calls and could leave a `library_watched_files` row without a
  corresponding `watcher_files` row, exactly the state `rescan_unlinked`
  exists to recover from.

  `attrs` must include `file_path`, `watch_dir`, and one of the entity FK
  columns (`movie_id`, `tv_series_id`, `movie_series_id`, `video_object_id`).
  """
  @spec record_seen(map()) :: {:ok, %WatchedFile{}} | {:error, term()}
  def record_seen(%{file_path: file_path, watch_dir: watch_dir} = attrs) do
    MediaCentarr.Repo.transaction(fn ->
      case Library.link_file(attrs) do
        {:ok, file} ->
          FilePresence.record_file(file_path, watch_dir)
          file

        {:error, reason} ->
          MediaCentarr.Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def init(dir) do
    Process.flag(:trap_exit, true)
    send(self(), :start_watching)
    :ok = MediaCentarr.Config.subscribe()

    {:ok,
     %__MODULE__{
       dir: dir,
       skip_dirs: load_skip_dirs(),
       exclude_dirs: ExcludeDirs.prepare(load_exclude_dirs(dir))
     }}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.state, state}
  def handle_call(:dir, _from, state), do: {:reply, state.dir, state}

  def handle_call(:scan, from, state) do
    dir = state.dir
    exclude_dirs = state.exclude_dirs

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      count = scan_directory(dir, exclude_dirs)
      GenServer.reply(from, {:ok, count})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:start_watching, state) do
    state = teardown_file_system(state)

    case FileSystem.start_link(dirs: [state.dir], recursive: true) do
      {:ok, pid} ->
        FileSystem.subscribe(pid)
        Log.info(:watcher, "started watching #{state.dir}")
        schedule_health_check()
        broadcast_state(state.dir, :watching)

        # Always scan on startup to catch files added while we were down (ADR-023)
        send(self(), {:auto_scan, recovery: state.was_unavailable})

        {:noreply,
         %{
           state
           | watcher_pid: pid,
             state: :watching,
             was_unavailable: false,
             device_id: read_device_id(state.dir)
         }}

      {:error, reason} ->
        Log.warning(
          :watcher,
          "could not start file_system watcher for #{state.dir}: #{inspect(reason)}"
        )

        schedule_health_check()
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable, was_unavailable: true, device_id: nil}}

      :ignore ->
        Log.warning(:watcher, "watcher unavailable — inotify-tools missing?")
        schedule_health_check()
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable, was_unavailable: true, device_id: nil}}
    end
  end

  def handle_info({:file_event, _pid, {path, events}}, state) do
    cond do
      :unmounted in events ->
        Log.warning(:watcher, "directory unmounted — #{state.dir}")
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable, was_unavailable: true, device_id: nil}}

      not interesting?(path, state) ->
        {:noreply, state}

      :created in events or :modified in events ->
        Log.info(:watcher, "detected file event — #{Path.basename(path)}, checking size")
        send(self(), {:check_size, path, nil, 0})
        {:noreply, state}

      :deleted in events ->
        {:noreply, buffer_deletion(state, path)}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    Log.warning(:watcher, "watcher stopped — #{state.dir}")
    {:noreply, state}
  end

  def handle_info({:check_size, path, last_size, count}, state) do
    case File.stat(path) do
      {:ok, %{size: size}} when size == last_size and count >= @size_stability_checks - 1 ->
        Log.info(:watcher, "size stabilized — #{Path.basename(path)}")
        detect_file(path, state.dir)
        {:noreply, state}

      {:ok, %{size: size}} ->
        Process.send_after(self(), {:check_size, path, size, count + 1}, @size_stability_interval)
        {:noreply, state}

      {:error, _} ->
        {:noreply, state}
    end
  end

  def handle_info(:health_check, state) do
    current_device_id = read_device_id(state.dir)

    case MountStatus.action(state.state, state.device_id, current_device_id) do
      :keep_watching ->
        schedule_health_check()
        {:noreply, state}

      :keep_unavailable ->
        schedule_health_check()
        {:noreply, state}

      :reinit_restored ->
        Log.info(:watcher, "directory restored — re-watching #{state.dir}")
        send(self(), :start_watching)
        {:noreply, %{state | state: :initializing}}

      :reinit_remount ->
        Log.info(:watcher, "device id changed — remount detected, re-watching #{state.dir}")
        send(self(), :start_watching)
        {:noreply, %{state | state: :initializing, was_unavailable: true}}

      :transition_unavailable ->
        Log.warning(:watcher, "directory inaccessible — #{state.dir}")
        broadcast_state(state.dir, :unavailable)
        schedule_health_check()
        {:noreply, %{state | state: :unavailable, was_unavailable: true, device_id: nil}}
    end
  end

  def handle_info({:auto_scan, opts}, state) do
    dir = state.dir
    exclude_dirs = state.exclude_dirs

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      scan_directory(dir, exclude_dirs, opts)
    end)

    {:noreply, state}
  end

  def handle_info(:auto_scan, state) do
    send(self(), {:auto_scan, recovery: false})
    {:noreply, state}
  end

  def handle_info({:config_updated, :exclude_dirs, _entries}, state) do
    state = refresh_exclude_dirs(state)
    count = length(state.exclude_dirs.entries)
    Log.info(:watcher, "exclude_dirs refreshed — #{count} entries (#{state.dir})")
    {:noreply, state}
  end

  def handle_info({:config_updated, _key, _value}, state), do: {:noreply, state}

  def handle_info(:flush_deletions, state) do
    flush_deletions(state, "flushed #{deletion_count(state)} deletion events")
    {:noreply, %{state | deletion_buffer: DeletionBuffer.new(), deletion_timer: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    flush_deletions(state, "flushed #{deletion_count(state)} buffered deletions — shutdown")
    :ok
  end

  defp deletion_count(state), do: state.deletion_buffer |> DeletionBuffer.paths() |> length()

  defp flush_deletions(state, log_message) do
    if not DeletionBuffer.empty?(state.deletion_buffer) do
      paths = DeletionBuffer.paths(state.deletion_buffer)
      Log.info(:watcher, log_message)

      FilePresence.mark_files_absent(paths)

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.library_file_events(),
        {:files_removed, paths}
      )
    end
  end

  defp interesting?(path, state) do
    VideoFile.video?(path) and
      not ExcludeDirs.excluded?(path, state.exclude_dirs) and
      not in_skip_dir?(path, state.skip_dirs)
  end

  defp buffer_deletion(state, path) do
    buffer = DeletionBuffer.add(state.deletion_buffer, path, state.dir)

    # Cancel existing timer and start a new one (sliding window debounce)
    if state.deletion_timer, do: Process.cancel_timer(state.deletion_timer)
    timer = Process.send_after(self(), :flush_deletions, @deletion_debounce_ms)

    %{state | deletion_buffer: buffer, deletion_timer: timer}
  end

  defp scan_directory(dir, %ExcludeDirs.Prepared{} = exclude_dirs, opts \\ []) do
    recovery = Keyword.get(opts, :recovery, false)
    Log.info(:watcher, "scanning #{dir}#{if recovery, do: " (recovery)", else: ""}")

    known_paths = FilePresence.known_file_paths(dir)
    scan_directory_with_paths(dir, exclude_dirs, known_paths, recovery: recovery)
  end

  defp scan_directory_with_paths(dir, %ExcludeDirs.Prepared{} = exclude_dirs, known_paths, opts) do
    start_time = System.monotonic_time()
    skip_dirs = load_skip_dirs()

    video_files =
      dir
      |> Walk.walk(exclude_dirs, skip_dirs)
      |> Enum.filter(&VideoFile.video?/1)

    new_files = Enum.reject(video_files, fn path -> MapSet.member?(known_paths, path) end)

    dispatched =
      Enum.reduce(new_files, 0, fn path, count ->
        detect_file(path, dir)
        count + 1
      end)

    # Restore any absent files that are now present on disk
    restored_paths = FilePresence.restore_present_files(dir, video_files)

    restored_entity_ids =
      if restored_paths == [] do
        []
      else
        unique_entity_ids(Library.list_files_by_paths(restored_paths))
      end

    broadcast_entities_changed(restored_entity_ids)

    # On recovery from :unavailable, re-push ALL entities for this watch dir
    # so the channel re-serializes with now-available image paths
    if Keyword.get(opts, :recovery, false) do
      all_files = Library.list_files_by_watch_dir(dir)
      all_entity_ids = unique_entity_ids(all_files)
      additional_ids = all_entity_ids -- restored_entity_ids

      if additional_ids != [] do
        Log.info(
          :watcher,
          "re-pushed #{length(additional_ids)} entities — recovery image re-resolution"
        )

        broadcast_entities_changed(additional_ids)
      end
    end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:media_centarr, :watcher, :scan, :stop],
      %{duration: duration},
      %{
        dir: dir,
        total_video_files: length(video_files),
        known: length(video_files) - dispatched,
        dispatched: dispatched,
        restored: length(restored_entity_ids)
      }
    )

    Log.info(
      :watcher,
      "scan completed — #{dispatched} new, #{length(restored_entity_ids)} restored, #{length(video_files)} total"
    )

    dispatched
  end

  defp detect_file(path, watch_dir) do
    Log.info(:watcher, "detected #{Path.basename(path)}")
    FilePresence.record_file(path, watch_dir)

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.pipeline_input(),
      {:file_detected, %{path: path, watch_dir: watch_dir}}
    )

    :ok
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp read_device_id(path) do
    case File.stat(path) do
      {:ok, %{major_device: major, minor_device: minor}} -> {major, minor}
      {:error, _} -> nil
    end
  end

  defp teardown_file_system(%{watcher_pid: nil} = state), do: state

  defp teardown_file_system(%{watcher_pid: pid} = state) do
    if Process.alive?(pid) do
      # Unlink first so the resulting EXIT signal isn't delivered as an
      # unhandled message to this trap_exit'd GenServer.
      Process.unlink(pid)
      Process.exit(pid, :shutdown)
    end

    %{state | watcher_pid: nil}
  end

  defp load_skip_dirs do
    Enum.map(MediaCentarr.Config.get(:skip_dirs) || [], &String.downcase/1)
  end

  defp in_skip_dir?(path, skip_dirs) do
    path
    |> Path.split()
    |> Enum.drop(-1)
    |> Enum.any?(fn component -> String.downcase(component) in skip_dirs end)
  end

  defp refresh_exclude_dirs(state) do
    %{state | exclude_dirs: ExcludeDirs.prepare(load_exclude_dirs(state.dir))}
  end

  defp load_exclude_dirs(watch_dir) do
    configured = MediaCentarr.Config.get(:exclude_dirs) || []
    images_dir = MediaCentarr.Config.images_dir_for(watch_dir)
    staging_base = MediaCentarr.Config.staging_base_for(watch_dir)

    auto_excludes =
      Enum.filter([images_dir, staging_base], &String.starts_with?(&1, watch_dir <> "/"))

    Enum.uniq(configured ++ auto_excludes)
  end

  defp broadcast_state(dir, internal_state) do
    state = if internal_state == :watching, do: :available, else: :unavailable

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.dir_state(),
      {:dir_state_changed, dir, :watch_dir, state}
    )
  end

  defp unique_entity_ids(records) do
    records
    |> Enum.map(&WatchedFile.owner_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp broadcast_entities_changed([]), do: :ok

  defp broadcast_entities_changed(entity_ids) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.library_updates(),
      {:entities_changed, entity_ids}
    )
  end
end
