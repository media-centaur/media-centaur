defmodule MediaCentaur.Watcher.Supervisor do
  @moduledoc """
  Coordinates multiple `MediaCentaur.Watcher` instances, one per watched directory.

  Starts a `DynamicSupervisor` and a `Registry`, then launches one Watcher child
  per directory from `Config.get(:watch_dirs)`.
  """
  use Supervisor
  require MediaCentaur.Log, as: Log

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: MediaCentaur.Watcher.Registry},
      {Registry, keys: :unique, name: MediaCentaur.DirMonitor.Registry},
      {DynamicSupervisor, name: MediaCentaur.Watcher.DynamicSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: MediaCentaur.DirMonitor.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all, max_restarts: 5, max_seconds: 60)
  end

  @doc """
  Called after the supervisor starts to launch a watcher for each configured directory.
  """
  def start_watchers do
    dirs = MediaCentaur.Config.get(:watch_dirs) || []

    Enum.each(dirs, fn dir ->
      case DynamicSupervisor.start_child(
             MediaCentaur.Watcher.DynamicSupervisor,
             {MediaCentaur.Watcher, dir}
           ) do
        {:ok, _pid} ->
          Log.info(:watcher, "started watcher — #{dir}")

        {:error, {:already_started, _pid}} ->
          Log.info(:watcher, "watcher already running — #{dir}")

        {:error, reason} ->
          Log.warning(:watcher, "failed to start watcher — #{dir}: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Starts a DirMonitor for each image directory that needs independent monitoring.
  """
  def start_image_dir_monitors do
    pairs = MediaCentaur.Config.image_dirs_needing_monitoring()

    Enum.each(pairs, fn {watch_dir, image_dir} ->
      case DynamicSupervisor.start_child(
             MediaCentaur.DirMonitor.DynamicSupervisor,
             {MediaCentaur.DirMonitor, {image_dir, watch_dir}}
           ) do
        {:ok, _pid} ->
          Log.info(:watcher, "started image dir monitor — #{image_dir}")

        {:error, {:already_started, _pid}} ->
          Log.info(:watcher, "image dir monitor already running — #{image_dir}")

        {:error, reason} ->
          Log.warning(
            :watcher,
            "failed to start image dir monitor for #{image_dir}: #{inspect(reason)}"
          )
      end
    end)
  end

  @doc """
  Returns a list of `%{dir: path, watch_dir: path, state: atom}` for all running DirMonitors.
  """
  def image_dir_statuses do
    MediaCentaur.DirMonitor.Registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.flat_map(fn {dir, pid} ->
      try do
        [
          %{
            dir: dir,
            watch_dir: MediaCentaur.DirMonitor.watch_dir(pid),
            state: MediaCentaur.DirMonitor.status(pid)
          }
        ]
      catch
        :exit, _ -> []
      end
    end)
    |> Enum.sort_by(& &1.dir)
  end

  @doc """
  Stops all watchers, runs `fun`, then restarts them.

  Used by destructive admin operations (clear_database) to prevent
  the watcher from re-detecting files during the operation.
  """
  def pause_during(fun) when is_function(fun, 0) do
    if Process.whereis(__MODULE__) do
      stop_watchers()

      try do
        fun.()
      after
        start_watchers()
      end
    else
      fun.()
    end
  end

  @doc """
  Aggregate status: `:watching` if any child is watching, `:unavailable` if all are down.
  """
  def status do
    statuses = statuses()

    cond do
      statuses == [] -> :unavailable
      Enum.any?(statuses, fn %{state: s} -> s == :watching end) -> :watching
      true -> :unavailable
    end
  end

  @doc """
  Returns a list of `%{dir: path, state: atom}` for all running watchers.
  """
  def statuses do
    MediaCentaur.Watcher.Registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.flat_map(fn {dir, pid} ->
      try do
        [%{dir: dir, state: MediaCentaur.Watcher.status(pid)}]
      catch
        :exit, _ -> []
      end
    end)
    |> Enum.sort_by(& &1.dir)
  end

  @doc """
  Scans all watched directories for video files not yet tracked.
  Returns `{:ok, total_count}`.
  """
  def scan do
    results =
      MediaCentaur.Watcher.Registry
      |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
      |> Enum.map(fn {_dir, pid} ->
        case MediaCentaur.Watcher.scan(pid) do
          {:ok, count} -> count
          _ -> 0
        end
      end)

    {:ok, Enum.sum(results)}
  end

  @doc """
  Returns true if any watcher is in a healthy state.
  """
  def media_dir_healthy? do
    status() == :watching
  end

  @doc "Returns true if any watcher children are currently running."
  def running? do
    DynamicSupervisor.which_children(MediaCentaur.Watcher.DynamicSupervisor) != []
  end

  @doc "Stops all running watcher children."
  def stop_watchers do
    MediaCentaur.Watcher.DynamicSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(MediaCentaur.Watcher.DynamicSupervisor, pid)
    end)
  end
end
