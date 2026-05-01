defmodule MediaCentarr.Watcher.Supervisor do
  @moduledoc """
  Coordinates multiple `MediaCentarr.Watcher` instances, one per watched directory.

  Starts a `DynamicSupervisor` and a `Registry`, then launches one Watcher child
  per directory from `Config.get(:watch_dirs)`.
  """
  use Supervisor
  import Ecto.Query
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Library
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics
  alias MediaCentarr.Watcher.DirMonitor
  alias MediaCentarr.Watcher.KnownFile

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
    normalize = fn entry ->
      %{
        "id" => entry["dir"],
        "dir" => entry["dir"],
        "images_dir" => nil,
        "name" => nil
      }
    end

    old_entries = currently_running_entries()
    new_normalized = Enum.map(new_entries, normalize)

    actions = MediaCentarr.Watcher.Reconciler.diff(old_entries, new_normalized)

    Enum.each(actions.to_stop, &stop_dir/1)

    Enum.each(actions.to_replace, fn %{old_dir: old, new: new} ->
      stop_dir(old)
      start_dir(new["dir"])
    end)

    Enum.each(actions.to_start, fn new -> start_dir(new["dir"]) end)

    count_summary =
      "start=#{length(actions.to_start)} stop=#{length(actions.to_stop)} replace=#{length(actions.to_replace)}"

    Log.info(:watcher, "reconcile — " <> count_summary)

    :ok
  end

  defp currently_running_entries do
    MediaCentarr.Watcher.Registry
    |> registered_keys()
    |> Enum.map(fn dir ->
      %{"id" => dir, "dir" => dir, "images_dir" => nil, "name" => nil}
    end)
  end

  defp start_dir(dir) do
    start_under(
      MediaCentarr.Watcher.DynamicSupervisor,
      {MediaCentarr.Watcher, dir},
      "watcher",
      dir
    )
  end

  defp stop_dir(dir) do
    case Registry.lookup(MediaCentarr.Watcher.Registry, dir) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(MediaCentarr.Watcher.DynamicSupervisor, pid)
      [] -> :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Match-spec returning every {key, pid} pair from a Registry. The ugly
  # `[{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}]` form is named once
  # here so `statuses/0`, `scan/0`, and `image_dir_statuses/0` don't have
  # to re-derive it.
  defp registered_pids(registry) do
    Registry.select(registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  defp registered_keys(registry) do
    Registry.select(registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  # Common shape for `DynamicSupervisor.start_child` + already-started + log.
  # `kind` is a short label used in the log message; `name` is the human
  # identifier (the watch dir or image dir).
  defp start_under(supervisor, child_spec, kind, name) do
    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, _pid} ->
        Log.info(:watcher, "started #{kind} — #{name}")
        :ok

      {:error, {:already_started, _pid}} ->
        Log.info(:watcher, "#{kind} already running — #{name}")
        :ok

      {:error, reason} ->
        Log.warning(:watcher, "failed to start #{kind} — #{name}: #{inspect(reason)}")
        {:error, reason}
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
      start_under(
        MediaCentarr.Watcher.DynamicSupervisor,
        {MediaCentarr.Watcher, dir},
        "watcher",
        dir
      )
    end)
  end

  @doc """
  Starts a DirMonitor for each image directory that needs independent monitoring.
  """
  def start_image_dir_monitors do
    pairs = MediaCentarr.Config.image_dirs_needing_monitoring()
    Enum.each(pairs, &start_image_monitor/1)
  end

  @doc """
  Reconciles running image-dir monitors with the desired set computed
  from `Config.image_dirs_needing_monitoring/0`. Called by
  `Watcher.ConfigListener` whenever watch_dirs change so that editing
  `images_dir` on a watch entry takes effect without an app restart.
  """
  @spec reconcile_image_dir_monitors() :: :ok
  def reconcile_image_dir_monitors do
    actions =
      MediaCentarr.Watcher.Reconciler.diff_image_monitors(
        currently_running_image_pairs(),
        MediaCentarr.Config.image_dirs_needing_monitoring()
      )

    Enum.each(actions.to_stop, &stop_image_monitor/1)
    Enum.each(actions.to_start, &start_image_monitor/1)

    if actions.to_start != [] or actions.to_stop != [] do
      Log.info(
        :watcher,
        "reconcile image monitors — start=#{length(actions.to_start)} stop=#{length(actions.to_stop)}"
      )
    end

    :ok
  end

  defp start_image_monitor({watch_dir, image_dir}) do
    start_under(
      MediaCentarr.Watcher.DirMonitor.DynamicSupervisor,
      {MediaCentarr.Watcher.DirMonitor, {image_dir, watch_dir}},
      "image dir monitor",
      image_dir
    )
  end

  defp stop_image_monitor(image_dir) do
    case Registry.lookup(MediaCentarr.Watcher.DirMonitor.Registry, image_dir) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(
          MediaCentarr.Watcher.DirMonitor.DynamicSupervisor,
          pid
        )

      [] ->
        :ok
    end
  end

  defp currently_running_image_pairs do
    DirMonitor.Registry
    |> registered_pids()
    |> Enum.flat_map(fn {image_dir, pid} ->
      try do
        [{DirMonitor.watch_dir(pid), image_dir}]
      catch
        :exit, _ -> []
      end
    end)
  end

  @doc """
  Returns a list of `%{dir: path, watch_dir: path, state: atom}` for all running DirMonitors.
  """
  def image_dir_statuses do
    DirMonitor.Registry
    |> registered_pids()
    |> Enum.flat_map(fn {dir, pid} ->
      try do
        [
          %{
            dir: dir,
            watch_dir: DirMonitor.watch_dir(pid),
            state: DirMonitor.status(pid)
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
      Enum.any?(statuses, fn %{state: state} -> state == :watching end) -> :watching
      true -> :unavailable
    end
  end

  @doc """
  Returns a list of `%{dir: path, state: atom}` for all running watchers.
  """
  def statuses do
    MediaCentarr.Watcher.Registry
    |> registered_pids()
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
      |> registered_pids()
      |> Enum.map(fn {_dir, pid} ->
        case MediaCentarr.Watcher.scan(pid) do
          {:ok, count} -> count
          _ -> 0
        end
      end)

    {:ok, Enum.sum(results)}
  end

  @doc """
  Re-emits `{:file_detected, ...}` events for every present file in
  `watcher_files` that has no link in `library_watched_files`.

  Recovery hook for stranded files — Discovery can drop a message when
  a downstream service (TMDB, network) fails transiently, and PubSub
  has no replay. Calling this after the underlying problem is resolved
  (e.g. the user updates an invalid TMDB API key) feeds those files
  back into the pipeline. Idempotent: Discovery's `already_linked?`
  check filters anything that has since been ingested.

  Returns `{:ok, count}` where `count` is the number of events emitted.
  """
  @spec rescan_unlinked() :: {:ok, non_neg_integer()}
  def rescan_unlinked do
    linked_paths = Library.linked_file_paths_subquery()

    rows =
      Repo.all(
        from k in KnownFile,
          where: k.state == :present and k.file_path not in subquery(linked_paths),
          select: %{path: k.file_path, watch_dir: k.watch_dir}
      )

    Enum.each(rows, fn row ->
      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        Topics.pipeline_input(),
        {:file_detected, %{path: row.path, watch_dir: row.watch_dir}}
      )
    end)

    count = length(rows)

    if count > 0 do
      Log.info(:watcher, "rescan_unlinked re-emitted #{count} stranded file_detected events")
    end

    {:ok, count}
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
