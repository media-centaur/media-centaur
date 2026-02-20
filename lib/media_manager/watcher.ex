defmodule MediaManager.Watcher do
  use GenServer
  require Logger

  @video_extensions ~w(.mkv .mp4 .avi .mov .wmv .m4v .ts .m2ts)
  @health_check_interval 30_000
  @size_stability_interval 5_000
  @size_stability_checks 2
  @burst_window_ms 2_000
  @burst_threshold 50

  defstruct [
    :media_dir,
    :watcher_pid,
    state: :initializing,
    removal_timestamps: [],
    pending_files: %{}
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def state, do: GenServer.call(__MODULE__, :state)
  def media_dir_healthy?, do: GenServer.call(__MODULE__, :media_dir_healthy)

  @impl true
  def init(_opts) do
    media_dir = MediaManager.Config.get(:media_dir)
    send(self(), :start_watching)
    {:ok, %__MODULE__{media_dir: media_dir}}
  end

  @impl true
  def handle_call(:state, _from, s), do: {:reply, s.state, s}

  @impl true
  def handle_call(:media_dir_healthy, _from, s) do
    healthy = s.state not in [:initializing, :media_dir_unavailable]
    {:reply, healthy, s}
  end

  @impl true
  def handle_info(:start_watching, s) do
    case FileSystem.start_link(dirs: [s.media_dir], recursive: true) do
      {:ok, pid} ->
        FileSystem.subscribe(pid)
        Logger.info("Watcher: started watching #{s.media_dir}")
        schedule_health_check()
        broadcast_state(:watching)
        {:noreply, %{s | watcher_pid: pid, state: :watching}}

      {:error, reason} ->
        Logger.warning("Watcher: could not start file_system watcher: #{inspect(reason)}")
        schedule_health_check()
        broadcast_state(:media_dir_unavailable)
        {:noreply, %{s | state: :media_dir_unavailable}}

      :ignore ->
        Logger.warning("Watcher: file_system watcher not available (inotify-tools missing?)")
        schedule_health_check()
        broadcast_state(:media_dir_unavailable)
        {:noreply, %{s | state: :media_dir_unavailable}}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, s) do
    cond do
      Enum.member?(events, :unmounted) ->
        Logger.warning("Watcher: media_dir unmounted")
        broadcast_state(:media_dir_unavailable)
        {:noreply, %{s | state: :media_dir_unavailable}}

      :removed in events or :deleted in events ->
        now = System.monotonic_time(:millisecond)
        cutoff = now - @burst_window_ms
        recent = Enum.filter(s.removal_timestamps, &(&1 >= cutoff))
        recent = [now | recent]

        if length(recent) >= @burst_threshold do
          Logger.warning("Watcher: suspicious burst of removal events detected")
          Phoenix.PubSub.broadcast(MediaManager.PubSub, "watcher:state", :suspicious_burst)
        end

        {:noreply, %{s | removal_timestamps: recent}}

      (:created in events or :modified in events) and video_file?(path) ->
        send(self(), {:check_size, path, nil, 0})
        {:noreply, s}

      true ->
        {:noreply, s}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, :stop}, s) do
    Logger.warning("Watcher: file_system watcher stopped")
    {:noreply, s}
  end

  @impl true
  def handle_info({:check_size, path, last_size, count}, s) do
    case File.stat(path) do
      {:ok, %{size: size}} when size == last_size and count >= @size_stability_checks - 1 ->
        detect_file(path)
        {:noreply, s}

      {:ok, %{size: size}} ->
        Process.send_after(self(), {:check_size, path, size, count + 1}, @size_stability_interval)
        {:noreply, s}

      {:error, _} ->
        {:noreply, s}
    end
  end

  @impl true
  def handle_info(:health_check, s) do
    case File.stat(s.media_dir) do
      {:ok, _} ->
        if s.state == :media_dir_unavailable do
          Logger.info("Watcher: media_dir is accessible again, re-watching")
          send(self(), :start_watching)
          {:noreply, %{s | state: :initializing}}
        else
          schedule_health_check()
          {:noreply, s}
        end

      {:error, _} ->
        if s.state != :media_dir_unavailable do
          Logger.warning("Watcher: media_dir is not accessible")
          broadcast_state(:media_dir_unavailable)
          {:noreply, %{s | state: :media_dir_unavailable}}
        else
          schedule_health_check()
          {:noreply, s}
        end
    end
  end

  defp detect_file(path) do
    case MediaManager.Library.WatchedFile
         |> Ash.Changeset.for_create(:detect, %{file_path: path})
         |> Ash.create() do
      {:ok, wf} ->
        Logger.info("Watcher: detected file #{path} as WatchedFile #{wf.id}")

      {:error, reason} ->
        Logger.warning("Watcher: failed to create WatchedFile for #{path}: #{inspect(reason)}")
    end
  end

  defp video_file?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in @video_extensions
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp broadcast_state(new_state) do
    Phoenix.PubSub.broadcast(
      MediaManager.PubSub,
      "watcher:state",
      {:watcher_state_changed, new_state}
    )
  end
end
