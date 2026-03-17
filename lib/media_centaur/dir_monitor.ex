defmodule MediaCentaur.DirMonitor do
  @moduledoc """
  Health-check-only monitor for image directories on separate drives.

  Unlike `Watcher`, this GenServer does not use inotify — it only runs a
  periodic `File.stat/1` check and broadcasts availability changes over
  PubSub using the unified `{:dir_state_changed, dir, :image_dir, state}`
  message format.

  One DirMonitor is started per image directory that is NOT a subdirectory
  of its watch directory (i.e., on a separate mount). Started and supervised
  by `Watcher.Supervisor`.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  @health_check_interval 30_000

  defstruct [:image_dir, :watch_dir, state: :checking]

  def start_link({image_dir, watch_dir}) do
    GenServer.start_link(__MODULE__, {image_dir, watch_dir},
      name: {:via, Registry, {MediaCentaur.DirMonitor.Registry, image_dir}}
    )
  end

  def status(pid), do: GenServer.call(pid, :status)
  def dir(pid), do: GenServer.call(pid, :dir)
  def watch_dir(pid), do: GenServer.call(pid, :watch_dir)

  @impl true
  def init({image_dir, watch_dir}) do
    send(self(), :health_check)
    {:ok, %__MODULE__{image_dir: image_dir, watch_dir: watch_dir}}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.state, state}
  def handle_call(:dir, _from, state), do: {:reply, state.image_dir, state}
  def handle_call(:watch_dir, _from, state), do: {:reply, state.watch_dir, state}

  @impl true
  def handle_info(:health_check, state) do
    new_state =
      case File.stat(state.image_dir) do
        {:ok, _} -> :available
        {:error, _} -> :unavailable
      end

    if new_state != state.state do
      Log.info(:watcher, "image dir #{state.image_dir} is now #{new_state}")
      broadcast_state(state.image_dir, new_state)
    end

    schedule_health_check()
    {:noreply, %{state | state: new_state}}
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp broadcast_state(dir, new_state) do
    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.dir_state(),
      {:dir_state_changed, dir, :image_dir, new_state}
    )
  end
end
