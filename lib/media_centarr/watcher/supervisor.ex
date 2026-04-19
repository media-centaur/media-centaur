defmodule MediaCentarr.Watcher.Supervisor do
  @moduledoc """
  Coordinates multiple `MediaCentarr.Watcher` instances, one per watched directory.

  Starts a `DynamicSupervisor` and a `Registry`, then launches one Watcher child
  per directory from `Config.get(:watch_dirs)`.
  """
  use Supervisor
  require MediaCentarr.Log, as: Log

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: MediaCentarr.Watcher.Registry},
      {Registry, keys: :unique, name: MediaCentarr.Watcher.DirMonitor.Registry},
      {DynamicSupervisor, name: MediaCentarr.Watcher.DynamicSupervisor, strategy: :one_for_one},
      {DynamicSupervisor,
       name: MediaCentarr.Watcher.DirMonitor.DynamicSupervisor, strategy: :one_for_one},
      MediaCentarr.Watcher.ConfigListener
    ]

    Supervisor.init(children, strategy: :one_for_all, max_restarts: 5, max_seconds: 60)
  end

  @doc """
  Reconciles the set of running watcher children with `new_entries`.
  Starts added entries, terminates removed ones, and replaces entries
  whose `dir` or `images_dir` changed. Name-only changes are no-ops.

  Called whenever `Config` broadcasts `{:config_updated, :watch_dirs, ...}`.
  """
  @spec reconcile([map()]) :: :ok
  def reconcile(new_entries) when is_list(new_entries) do
    old_entries = currently_running_entries()
    actions = MediaCentarr.Watcher.Reconciler.diff(old_entries, new_entries)

    Enum.each(actions.to_stop, &stop_dir/1)

    Enum.each(actions.to_replace, fn %{old_dir: old_dir, new: new_entry} ->
      stop_dir(old_dir)
      start_dir(new_entry["dir"])
    end)

    Enum.each(actions.to_start, fn new_entry -> start_dir(new_entry["dir"]) end)

    :ok
  end

  defp currently_running_entries do
    MediaCentarr.Watcher.Registry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.map(fn dir ->
      %{"id" => dir, "dir" => dir, "images_dir" => nil, "name" => nil}
    end)
  end

  defp start_dir(dir) do
    case DynamicSupervisor.start_child(
           MediaCentarr.Watcher.DynamicSupervisor,
           {MediaCentarr.Watcher, dir}
         ) do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _}} ->
        :ok

      {:error, reason} ->
        Log.warning(:watcher, "reconcile: failed to start #{dir}: #{inspect(reason)}")
    end
  end

  defp stop_dir(dir) do
    case Registry.lookup(MediaCentarr.Watcher.Registry, dir) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(MediaCentarr.Watcher.DynamicSupervisor, pid)
      [] -> :ok
    end
  end

  @doc "Subscribe the caller to watcher directory state change events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.dir_state())
  end

  @doc """
  Called after the supervisor starts to launch a watcher for each configured directory.
  """
  def start_watchers do
    dirs = MediaCentarr.Config.get(:watch_dirs) || []

    Enum.each(dirs, fn dir ->
      case DynamicSupervisor.start_child(
             MediaCentarr.Watcher.DynamicSupervisor,
             {MediaCentarr.Watcher, dir}
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
    pairs = MediaCentarr.Config.image_dirs_needing_monitoring()

    Enum.each(pairs, fn {watch_dir, image_dir} ->
      case DynamicSupervisor.start_child(
             MediaCentarr.Watcher.DirMonitor.DynamicSupervisor,
             {MediaCentarr.Watcher.DirMonitor, {image_dir, watch_dir}}
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
    MediaCentarr.Watcher.DirMonitor.Registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.flat_map(fn {dir, pid} ->
      try do
        [
          %{
            dir: dir,
            watch_dir: MediaCentarr.Watcher.DirMonitor.watch_dir(pid),
            state: MediaCentarr.Watcher.DirMonitor.status(pid)
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
    MediaCentarr.Watcher.Registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.flat_map(fn {dir, pid} ->
      try do
        [%{dir: dir, state: MediaCentarr.Watcher.status(pid)}]
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
      MediaCentarr.Watcher.Registry
      |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
      |> Enum.map(fn {_dir, pid} ->
        case MediaCentarr.Watcher.scan(pid) do
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
    DynamicSupervisor.which_children(MediaCentarr.Watcher.DynamicSupervisor) != []
  end

  @doc "Stops all running watcher children."
  def stop_watchers do
    MediaCentarr.Watcher.DynamicSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(MediaCentarr.Watcher.DynamicSupervisor, pid)
    end)
  end
end
