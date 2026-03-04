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
      {DynamicSupervisor, name: MediaCentaur.Watcher.DynamicSupervisor, strategy: :one_for_one}
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
          Log.info(:watcher, "started watcher for #{dir}")

        {:error, {:already_started, _pid}} ->
          Log.info(:watcher, "watcher already running for #{dir}")

        {:error, reason} ->
          Log.warning(:watcher, "failed to start watcher for #{dir}: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Stops all watchers, runs `fun`, then restarts them.

  Used by destructive admin operations (clear_database) to prevent
  the watcher from re-detecting files during the operation.
  """
  def pause_during(fun) when is_function(fun, 0) do
    if Process.whereis(__MODULE__) do
      stop_all_watchers()

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
  Aggregate state: `:watching` if any child is watching, `:unavailable` if all are down.
  """
  def state do
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
        [%{dir: dir, state: MediaCentaur.Watcher.state(pid)}]
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
    state() == :watching
  end

  defp stop_all_watchers do
    MediaCentaur.Watcher.DynamicSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(MediaCentaur.Watcher.DynamicSupervisor, pid)
    end)
  end
end
