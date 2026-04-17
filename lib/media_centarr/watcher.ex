defmodule MediaCentarr.Watcher do
  use Boundary, deps: [MediaCentarr.Library], exports: [Supervisor, FilePresence]

  @moduledoc """
  Watches a single directory for new video files via inotify.

  Each instance is started by `MediaCentarr.Watcher.Supervisor` and registers
  itself in `MediaCentarr.Watcher.Registry` with its directory path as key.

  ## Event-driven pipeline integration

  Instead of creating database records, the watcher broadcasts PubSub events
  to `MediaCentarr.Topics.pipeline_input()`. The Pipeline Producer subscribes to this topic and
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
  require MediaCentarr.Log, as: Log

  import Ecto.Query

  alias MediaCentarr.Library.WatchedFile
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics
  alias MediaCentarr.Watcher.FilePresence

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
    exclude_dirs: [],
    skip_dirs: []
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

  @impl true
  def init(dir) do
    Process.flag(:trap_exit, true)
    send(self(), :start_watching)

    {:ok, %__MODULE__{dir: dir, exclude_dirs: load_exclude_dirs(dir), skip_dirs: load_skip_dirs()}}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.state, state}
  def handle_call(:dir, _from, state), do: {:reply, state.dir, state}

  def handle_call(:scan, from, state) do
    dir = state.dir

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
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
        Log.warning(:watcher, "watcher unavailable — inotify-tools missing?")
        schedule_health_check()
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable, was_unavailable: true}}
    end
  end

  def handle_info({:file_event, _pid, {path, events}}, state) do
    cond do
      Enum.member?(events, :unmounted) ->
        Log.warning(:watcher, "directory unmounted — #{state.dir}")
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable, was_unavailable: true}}

      (:created in events or :modified in events) and video_file?(path) and
        not excluded?(path, state.exclude_dirs) and
          not in_skip_dir?(path, state.skip_dirs) ->
        Log.info(:watcher, "detected file event — #{Path.basename(path)}, checking size")
        send(self(), {:check_size, path, nil, 0})
        {:noreply, state}

      :deleted in events and video_file?(path) and not excluded?(path, state.exclude_dirs) and
          not in_skip_dir?(path, state.skip_dirs) ->
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

  def handle_info(:health_check, %{state: :watching} = state) do
    schedule_health_check()
    {:noreply, state}
  end

  def handle_info(:health_check, state) do
    case File.stat(state.dir) do
      {:ok, _} ->
        if state.state == :unavailable do
          Log.info(:watcher, "directory restored — re-watching #{state.dir}")
          send(self(), :start_watching)
          {:noreply, %{state | state: :initializing}}
        else
          schedule_health_check()
          {:noreply, state}
        end

      {:error, _} ->
        if state.state == :unavailable do
          schedule_health_check()
          {:noreply, state}
        else
          Log.warning(:watcher, "directory inaccessible — #{state.dir}")
          broadcast_state(state.dir, :unavailable)
          {:noreply, %{state | state: :unavailable, was_unavailable: true}}
        end
    end
  end

  def handle_info({:auto_scan, opts}, state) do
    dir = state.dir

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      scan_directory(dir, opts)
    end)

    {:noreply, state}
  end

  def handle_info(:auto_scan, state) do
    send(self(), {:auto_scan, recovery: false})
    {:noreply, state}
  end

  def handle_info(:flush_deletions, state) do
    if map_size(state.deletion_buffer) > 0 do
      paths = Map.keys(state.deletion_buffer)
      Log.info(:watcher, "flushed #{length(paths)} deletion events")

      FilePresence.mark_files_absent(paths)

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.library_file_events(),
        {:files_removed, paths}
      )
    end

    {:noreply, %{state | deletion_buffer: %{}, deletion_timer: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    if map_size(state.deletion_buffer) > 0 do
      paths = Map.keys(state.deletion_buffer)
      Log.info(:watcher, "flushed #{length(paths)} buffered deletions — shutdown")

      FilePresence.mark_files_absent(paths)

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.library_file_events(),
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

    known_paths = FilePresence.known_file_paths(dir)
    scan_directory_with_paths(dir, known_paths, recovery: recovery)
  end

  defp scan_directory_with_paths(dir, known_paths, opts) do
    start_time = System.monotonic_time()
    exclude_dirs = load_exclude_dirs(dir)
    skip_dirs = load_skip_dirs()

    video_files =
      dir
      |> walk_files(exclude_dirs, skip_dirs)
      |> Enum.filter(&video_file?/1)

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
        unique_entity_ids(files_by_paths(restored_paths))
      end

    broadcast_entities_changed(restored_entity_ids)

    # On recovery from :unavailable, re-push ALL entities for this watch dir
    # so the channel re-serializes with now-available image paths
    if Keyword.get(opts, :recovery, false) do
      all_files = files_by_watch_dir(dir)
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

  defp video_file?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in @video_extensions
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
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

  defp load_exclude_dirs(watch_dir) do
    configured = MediaCentarr.Config.get(:exclude_dirs) || []
    images_dir = MediaCentarr.Config.images_dir_for(watch_dir)
    staging_base = MediaCentarr.Config.staging_base_for(watch_dir)

    auto_excludes =
      Enum.filter([images_dir, staging_base], &String.starts_with?(&1, watch_dir <> "/"))

    Enum.uniq(configured ++ auto_excludes)
  end

  defp walk_files(dir, exclude_dirs, skip_dirs) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          path = Path.join(dir, entry)

          cond do
            excluded?(path, exclude_dirs) -> []
            File.dir?(path) and String.downcase(entry) in skip_dirs -> []
            File.dir?(path) -> walk_files(path, exclude_dirs, skip_dirs)
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

  defp broadcast_state(dir, internal_state) do
    state = if internal_state == :watching, do: :available, else: :unavailable

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.dir_state(),
      {:dir_state_changed, dir, :watch_dir, state}
    )
  end

  # ---------------------------------------------------------------------------
  # Library table reads (direct Repo queries, no context coupling)
  # ---------------------------------------------------------------------------

  defp files_by_paths(paths) do
    Repo.all(from(w in WatchedFile, where: w.file_path in ^paths))
  end

  defp files_by_watch_dir(watch_dir) do
    Repo.all(from(w in WatchedFile, where: w.watch_dir == ^watch_dir))
  end

  defp unique_entity_ids(records) do
    records
    |> Enum.map(&(&1.tv_series_id || &1.movie_series_id || &1.movie_id || &1.video_object_id))
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
