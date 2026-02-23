defmodule MediaManager.Watcher do
  @moduledoc """
  Watches a single directory for new video files via inotify.

  Each instance is started by `MediaManager.Watcher.Supervisor` and registers
  itself in `MediaManager.Watcher.Registry` with its directory path as key.
  """
  use GenServer
  require Logger

  @video_extensions ~w(.mkv .mp4 .avi .mov .wmv .m4v .ts .m2ts)
  @health_check_interval 30_000
  @size_stability_interval 5_000
  @size_stability_checks 2
  @burst_window_ms 2_000
  @burst_threshold 50

  defstruct [
    :dir,
    :watcher_pid,
    state: :initializing,
    removal_timestamps: [],
    pending_files: %{}
  ]

  def start_link(dir) do
    GenServer.start_link(__MODULE__, dir,
      name: {:via, Registry, {MediaManager.Watcher.Registry, dir}}
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
    send(self(), :start_watching)
    {:ok, %__MODULE__{dir: dir}}
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state.state, state}

  @impl true
  def handle_call(:dir, _from, state), do: {:reply, state.dir, state}

  @impl true
  def handle_call(:scan, from, state) do
    dir = state.dir

    Task.Supervisor.start_child(MediaManager.TaskSupervisor, fn ->
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
        Logger.info("Watcher: started watching #{state.dir}")
        schedule_health_check()
        broadcast_state(state.dir, :watching)
        {:noreply, %{state | watcher_pid: pid, state: :watching}}

      {:error, reason} ->
        Logger.warning(
          "Watcher: could not start file_system watcher for #{state.dir}: #{inspect(reason)}"
        )

        schedule_health_check()
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable}}

      :ignore ->
        Logger.warning("Watcher: file_system watcher not available (inotify-tools missing?)")
        schedule_health_check()
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable}}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    cond do
      Enum.member?(events, :unmounted) ->
        Logger.warning("Watcher: directory unmounted: #{state.dir}")
        broadcast_state(state.dir, :unavailable)
        {:noreply, %{state | state: :unavailable}}

      :removed in events or :deleted in events ->
        now = System.monotonic_time(:millisecond)
        cutoff = now - @burst_window_ms

        recent =
          [now | Enum.filter(state.removal_timestamps, &(&1 >= cutoff))]
          |> Enum.take(@burst_threshold)

        if length(recent) >= @burst_threshold do
          Logger.warning("Watcher: suspicious burst of removal events detected in #{state.dir}")
          Phoenix.PubSub.broadcast(MediaManager.PubSub, "watcher:state", :suspicious_burst)
        end

        {:noreply, %{state | removal_timestamps: recent}}

      (:created in events or :modified in events) and video_file?(path) and
          not excluded?(path, exclude_dirs()) ->
        send(self(), {:check_size, path, nil, 0})
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.warning("Watcher: file_system watcher stopped for #{state.dir}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:check_size, path, last_size, count}, state) do
    case File.stat(path) do
      {:ok, %{size: size}} when size == last_size and count >= @size_stability_checks - 1 ->
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
  def handle_info(:health_check, state) do
    case File.stat(state.dir) do
      {:ok, _} ->
        if state.state == :unavailable do
          Logger.info("Watcher: directory is accessible again, re-watching #{state.dir}")
          send(self(), :start_watching)
          {:noreply, %{state | state: :initializing}}
        else
          schedule_health_check()
          {:noreply, state}
        end

      {:error, _} ->
        if state.state != :unavailable do
          Logger.warning("Watcher: directory is not accessible: #{state.dir}")
          broadcast_state(state.dir, :unavailable)
          {:noreply, %{state | state: :unavailable}}
        else
          schedule_health_check()
          {:noreply, state}
        end
    end
  end

  defp scan_directory(dir) do
    exclude_dirs = exclude_dirs()
    pattern = Path.join(dir, "**/*")

    pattern
    |> Path.wildcard()
    |> Enum.reject(&excluded?(&1, exclude_dirs))
    |> Enum.filter(&video_file?/1)
    |> Enum.reduce(0, fn path, count ->
      case detect_file(path, dir) do
        :ok -> count + 1
        :skipped -> count
      end
    end)
  end

  defp detect_file(path, watch_dir) do
    case MediaManager.Library.WatchedFile
         |> Ash.Changeset.for_create(:detect, %{file_path: path, watch_dir: watch_dir})
         |> Ash.create() do
      {:ok, file} ->
        Logger.info("Watcher: detected file #{path} as WatchedFile #{file.id}")
        :ok

      {:error, _reason} ->
        :skipped
    end
  end

  defp video_file?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in @video_extensions
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp exclude_dirs do
    MediaManager.Config.get(:exclude_dirs) || []
  end

  defp excluded?(path, exclude_dirs) do
    Enum.any?(exclude_dirs, fn dir ->
      String.starts_with?(path, dir <> "/") or path == dir
    end)
  end

  defp broadcast_state(dir, new_state) do
    Phoenix.PubSub.broadcast(
      MediaManager.PubSub,
      "watcher:state",
      {:watcher_state_changed, dir, new_state}
    )
  end
end
