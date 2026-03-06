defmodule MediaCentaur.Watcher do
  @moduledoc """
  Watches a single directory for new video files via inotify.

  Each instance is started by `MediaCentaur.Watcher.Supervisor` and registers
  itself in `MediaCentaur.Watcher.Registry` with its directory path as key.

  ## Event-driven pipeline integration

  Instead of creating database records, the watcher broadcasts PubSub events
  to `"pipeline:input"`. The Pipeline Producer subscribes to this topic and
  converts events into Payloads for Broadway processing.

  - `detect_file/2` broadcasts `{:file_detected, %{path, watch_dir}}`
  - `scan_directory/1` reads existing WatchedFile file_paths to skip already-processed files

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
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.{FileTracker, Helpers}

  @video_extensions ~w(.mkv .mp4 .avi .mov .wmv .m4v .ts .m2ts)
  @health_check_interval 30_000
  @size_stability_interval 5_000
  @size_stability_checks 2
  @deletion_debounce_ms 3_000
  defstruct [
    :dir,
    :watcher_pid,
    :deletion_timer,
    state: :initializing,
    was_unavailable: false,
    pending_files: %{},
    deletion_buffer: %{},
    exclude_dirs: []
  ]

  def start_link(dir) do
    GenServer.start_link(__MODULE__, dir,
      name: {:via, Registry, {MediaCentaur.Watcher.Registry, dir}}
    )
  end

  def state(pid), do: GenServer.call(pid, :state)
  def dir(pid), do: GenServer.call(pid, :dir)

  @doc """
  Walks the watched directory recursively, detects video files not yet tracked.
  Returns `{:ok, count}` where count is the number of newly detected files.
  """
  def scan(pid), do: GenServer.call(pid, :scan, 60_000)

  @impl true
  def init(dir) do
    Process.flag(:trap_exit, true)
    send(self(), :start_watching)
    {:ok, %__MODULE__{dir: dir, exclude_dirs: load_exclude_dirs(dir)}}
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state.state, state}

  @impl true
  def handle_call(:dir, _from, state), do: {:reply, state.dir, state}

  @impl true
  def handle_call(:scan, from, state) do
    dir = state.dir

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      count = scan_directory(dir)
      GenServer.reply(from, {:ok, count})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:start_watching, state) do
    case FileSystem.start_link(dirs: [state.dir], recursive: true) do
      {:ok, pid} ->
        FileSystem.subscribe(pid)
        Log.info(:watcher, "started watching #{state.dir}")
        schedule_health_check()
        broadcast_state(state.dir, :watching)

        # Always scan on startup to catch files added while we were down (ADR-023)
        send(self(), {:auto_scan, recovery: state.was_unavailable})

        {:noreply, %{state | watcher_pid: pid, state: :watching, was_unavailable: false}}

      {:error, reason} ->
        Log.warning(
          :watcher,
          "could not start file_system watcher for #{state.dir}: #{inspect(reason)}"
        )

        schedule_health_check()
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable, was_unavailable: true}}

      :ignore ->
        Log.warning(:watcher, "file_system watcher not available (inotify-tools missing?)")
        schedule_health_check()
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable, was_unavailable: true}}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    cond do
      Enum.member?(events, :unmounted) ->
        Log.warning(:watcher, "directory unmounted: #{state.dir}")
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable, was_unavailable: true}}

      (:created in events or :modified in events) and video_file?(path) and
          not excluded?(path, state.exclude_dirs) ->
        Log.info(:watcher, "file event for #{Path.basename(path)}, starting size checks")
        send(self(), {:check_size, path, nil, 0})
        {:noreply, state}

      :deleted in events and video_file?(path) and not excluded?(path, state.exclude_dirs) ->
        {:noreply, buffer_deletion(state, path)}

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, :stop}, state) do
    Log.warning(:watcher, "file_system watcher stopped for #{state.dir}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:check_size, path, last_size, count}, state) do
    case File.stat(path) do
      {:ok, %{size: size}} when size == last_size and count >= @size_stability_checks - 1 ->
        Log.info(:watcher, "size stable for #{Path.basename(path)}, detecting")
        detect_file(path, state.dir)
        {:noreply, state}

      {:ok, %{size: size}} ->
        Process.send_after(self(), {:check_size, path, size, count + 1}, @size_stability_interval)
        {:noreply, state}

      {:error, _} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:health_check, %{state: :watching} = state) do
    schedule_health_check()
    {:noreply, state}
  end

  def handle_info(:health_check, state) do
    case File.stat(state.dir) do
      {:ok, _} ->
        if state.state == :unavailable do
          Log.info(:watcher, "directory accessible again, re-watching #{state.dir}")
          send(self(), :start_watching)
          {:noreply, %{state | state: :initializing}}
        else
          schedule_health_check()
          {:noreply, state}
        end

      {:error, _} ->
        if state.state != :unavailable do
          Log.warning(:watcher, "directory is not accessible: #{state.dir}")
          broadcast_state(state.dir, :unavailable)
          {:noreply, %{state | state: :unavailable, was_unavailable: true}}
        else
          schedule_health_check()
          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info({:auto_scan, opts}, state) do
    dir = state.dir

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      scan_directory(dir, opts)
    end)

    {:noreply, state}
  end

  def handle_info(:auto_scan, state) do
    send(self(), {:auto_scan, recovery: false})
    {:noreply, state}
  end

  @impl true
  def handle_info(:flush_deletions, state) do
    if map_size(state.deletion_buffer) > 0 do
      paths = Map.keys(state.deletion_buffer)
      Log.info(:watcher, "flushing #{length(paths)} deletion events")

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        "library:file_events",
        {:files_removed, paths}
      )
    end

    {:noreply, %{state | deletion_buffer: %{}, deletion_timer: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    if map_size(state.deletion_buffer) > 0 do
      paths = Map.keys(state.deletion_buffer)
      Log.info(:watcher, "flushing #{length(paths)} buffered deletions on shutdown")

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        "library:file_events",
        {:files_removed, paths}
      )
    end

    :ok
  end

  defp buffer_deletion(state, path) do
    buffer = Map.put(state.deletion_buffer, path, state.dir)

    # Cancel existing timer and start a new one (sliding window debounce)
    if state.deletion_timer, do: Process.cancel_timer(state.deletion_timer)
    timer = Process.send_after(self(), :flush_deletions, @deletion_debounce_ms)

    %{state | deletion_buffer: buffer, deletion_timer: timer}
  end

  defp scan_directory(dir, opts \\ []) do
    recovery = Keyword.get(opts, :recovery, false)
    Log.info(:watcher, "scanning #{dir}#{if recovery, do: " (recovery)", else: ""}")

    case fetch_known_file_paths() do
      {:ok, known_paths} ->
        scan_directory_with_paths(dir, known_paths, recovery: recovery)

      {:error, _reason} ->
        Log.info(:watcher, "scan skipped, database not available")
        0
    end
  end

  defp scan_directory_with_paths(dir, known_paths, opts) do
    start_time = System.monotonic_time()
    exclude_dirs = load_exclude_dirs(dir)

    video_files =
      dir
      |> walk_files(exclude_dirs)
      |> Enum.filter(&video_file?/1)

    new_files = Enum.reject(video_files, fn path -> MapSet.member?(known_paths, path) end)

    dispatched =
      Enum.reduce(new_files, 0, fn path, count ->
        detect_file(path, dir)
        count + 1
      end)

    # Restore any absent files that are now present on disk
    restored_entity_ids = FileTracker.restore_present_files(dir, video_files)
    Helpers.broadcast_entities_changed(restored_entity_ids)

    # On recovery from :unavailable, re-push ALL entities for this watch dir
    # so the channel re-serializes with now-available image paths
    if Keyword.get(opts, :recovery, false) do
      complete_files = Library.list_files_by_watch_dir!(dir, :complete)
      all_entity_ids = Helpers.unique_entity_ids(complete_files)
      additional_ids = all_entity_ids -- restored_entity_ids

      if additional_ids != [] do
        Log.info(
          :watcher,
          "recovery: re-pushing #{length(additional_ids)} entities for image re-resolution"
        )

        Helpers.broadcast_entities_changed(additional_ids)
      end
    end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:media_centaur, :watcher, :scan, :stop],
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
      "scan complete: #{dispatched} new, #{length(restored_entity_ids)} restored, #{length(video_files)} total"
    )

    dispatched
  end

  defp detect_file(path, watch_dir) do
    Log.info(:watcher, "detected #{Path.basename(path)}")

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      "pipeline:input",
      {:file_detected, %{path: path, watch_dir: watch_dir}}
    )

    :ok
  end

  defp fetch_known_file_paths do
    case Library.list_watched_files() do
      {:ok, files} -> {:ok, MapSet.new(files, & &1.file_path)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp video_file?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in @video_extensions
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp load_exclude_dirs(watch_dir) do
    configured = MediaCentaur.Config.get(:exclude_dirs) || []
    images_dir = MediaCentaur.Config.images_dir_for(watch_dir)
    staging_base = MediaCentaur.Config.staging_base_for(watch_dir)

    auto_excludes =
      [images_dir, staging_base]
      |> Enum.filter(&String.starts_with?(&1, watch_dir <> "/"))

    Enum.uniq(configured ++ auto_excludes)
  end

  defp walk_files(dir, exclude_dirs) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          path = Path.join(dir, entry)

          cond do
            excluded?(path, exclude_dirs) -> []
            File.dir?(path) -> walk_files(path, exclude_dirs)
            true -> [path]
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp excluded?(path, exclude_dirs) do
    Enum.any?(exclude_dirs, fn dir ->
      String.starts_with?(path, dir <> "/") or path == dir
    end)
  end

  defp broadcast_state(dir, new_state) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      "watcher:state",
      {:watcher_state_changed, dir, new_state}
    )
  end
end
