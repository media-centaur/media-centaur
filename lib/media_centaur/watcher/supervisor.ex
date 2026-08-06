defmodule MediaCentaur.Watcher.Supervisor do
  @moduledoc """
  Coordinates multiple `MediaCentaur.Watcher` instances, one per watched directory.

  Starts a `DynamicSupervisor` and a `Registry`, then launches one Watcher child
  per directory from `Config.get(:media_dirs)`.
  """
  use Supervisor
  import Ecto.Query
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics
  alias MediaCentaur.Watcher.DirMonitor
  alias MediaCentaur.Library.FilePresence

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      MediaCentaur.Watcher.ScanStats,
      {Registry, keys: :unique, name: MediaCentaur.Watcher.Registry},
      {Registry, keys: :unique, name: MediaCentaur.Watcher.DirMonitor.Registry},
      {DynamicSupervisor, name: MediaCentaur.Watcher.DynamicSupervisor, strategy: :one_for_one},
      {DynamicSupervisor,
       name: MediaCentaur.Watcher.DirMonitor.DynamicSupervisor, strategy: :one_for_one},
      MediaCentaur.Watcher.ConfigListener
    ]

    Supervisor.init(children, strategy: :one_for_all, max_restarts: 5, max_seconds: 60)
  end

  @doc """
  Reconciles the set of running watcher children with `new_entries`.
  Starts added entries, terminates removed ones, and replaces entries
  whose `dir` or `images_dir` changed. Name-only changes are no-ops.

  Called whenever `Config` broadcasts `{:config_updated, :media_dirs, ...}`.
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

    actions = MediaCentaur.Watcher.Reconciler.diff(old_entries, new_normalized)

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
    MediaCentaur.Watcher.Registry
    |> registered_keys()
    |> Enum.map(fn dir ->
      %{"id" => dir, "dir" => dir, "images_dir" => nil, "name" => nil}
    end)
  end

  defp start_dir(dir) do
    start_under(
      MediaCentaur.Watcher.DynamicSupervisor,
      {MediaCentaur.Watcher, dir},
      "watcher",
      dir
    )
  end

  defp stop_dir(dir) do
    case Registry.lookup(MediaCentaur.Watcher.Registry, dir) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(MediaCentaur.Watcher.DynamicSupervisor, pid)
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
  # identifier (the media dir or image dir).
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
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.dir_state())
  end

  @doc """
  Called after the supervisor starts to launch a watcher for each configured directory.
  """
  def start_watchers do
    dirs = MediaCentaur.Config.get(:media_dirs) || []

    Enum.each(dirs, fn dir ->
      start_under(
        MediaCentaur.Watcher.DynamicSupervisor,
        {MediaCentaur.Watcher, dir},
        "watcher",
        dir
      )
    end)
  end

  @doc """
  Starts a DirMonitor for each image directory that needs independent monitoring.
  """
  def start_image_dir_monitors do
    pairs = MediaCentaur.Config.image_dirs_needing_monitoring()
    Enum.each(pairs, &start_image_monitor/1)
  end

  @doc """
  Reconciles running image-dir monitors with the desired set computed
  from `Config.image_dirs_needing_monitoring/0`. Called by
  `Watcher.ConfigListener` whenever media_dirs change so that editing
  `images_dir` on a watch entry takes effect without an app restart.
  """
  @spec reconcile_image_dir_monitors() :: :ok
  def reconcile_image_dir_monitors do
    actions =
      MediaCentaur.Watcher.Reconciler.diff_image_monitors(
        currently_running_image_pairs(),
        MediaCentaur.Config.image_dirs_needing_monitoring()
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

  defp start_image_monitor({media_dir, image_dir}) do
    start_under(
      MediaCentaur.Watcher.DirMonitor.DynamicSupervisor,
      {MediaCentaur.Watcher.DirMonitor, {image_dir, media_dir}},
      "image dir monitor",
      image_dir
    )
  end

  defp stop_image_monitor(image_dir) do
    case Registry.lookup(MediaCentaur.Watcher.DirMonitor.Registry, image_dir) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(
          MediaCentaur.Watcher.DirMonitor.DynamicSupervisor,
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
        [{DirMonitor.media_dir(pid), image_dir}]
      catch
        :exit, _ -> []
      end
    end)
  end

  @doc """
  Returns a list of `%{dir: path, media_dir: path, state: atom}` for all running DirMonitors.
  """
  def image_dir_statuses do
    DirMonitor.Registry
    |> registered_pids()
    |> Enum.flat_map(fn {dir, pid} ->
      try do
        [
          %{
            dir: dir,
            media_dir: DirMonitor.media_dir(pid),
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
  Returns a list of per-watcher status maps for all running watchers:

      %{dir: path, state: atom, reason: atom | nil,
        settling_count: non_neg_integer, pending_deletions: non_neg_integer}

  `dir` and `state` are the load-bearing keys (consumed by `status/0` and, via
  `MediaCentaur.WatcherStatus`, by `Library.Availability`); the rest drive the
  Status page's watcher activity narrative and are purely additive.
  """
  def statuses do
    MediaCentaur.Watcher.Registry
    |> registered_pids()
    |> Enum.flat_map(fn {dir, pid} ->
      try do
        [Map.put(MediaCentaur.Watcher.status_detail(pid), :dir, dir)]
      catch
        :exit, _ -> []
      end
    end)
    |> Enum.sort_by(& &1.dir)
  end

  @doc """
  Returns the retained `%{dir => last_scan_summary}` map from
  `MediaCentaur.Watcher.ScanStats` — the boundary-clean door for the web layer,
  which may only call this exported `Supervisor`.
  """
  defdelegate scan_stats(), to: MediaCentaur.Watcher.ScanStats, as: :all

  @doc """
  Scans all watched directories for video files not yet tracked.
  Returns `{:ok, total_count}`.
  """
  def scan do
    results =
      MediaCentaur.Watcher.Registry
      |> registered_pids()
      |> Enum.map(fn {_dir, pid} ->
        case MediaCentaur.Watcher.scan(pid) do
          {:ok, count} -> count
          _ -> 0
        end
      end)

    {:ok, Enum.sum(results)}
  end

  @doc """
  Fire-and-forget library rescan. Runs the (blocking) `scan/0` on a
  supervised task so web-layer callers don't block and don't own the
  work — the rescan must complete regardless of the triggering
  LiveView's lifecycle (ADR-049: must-outlive background work lives in
  the context layer, not a web-layer `start_child`).
  """
  def scan_async do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn -> scan() end)
    :ok
  end

  @doc """
  Re-emits `{:file_detected, ...}` events for every `Library.FilePresence`
  row that has no matching link in `library_watched_files` and still
  exists on disk.

  Recovery hook for stranded files — Discovery can drop a message when
  a downstream service (TMDB, network) fails transiently, and PubSub
  has no replay. Calling this after the underlying problem is resolved
  (e.g. the user updates an invalid TMDB API key) feeds those files
  back into the pipeline. Idempotent: Discovery's `already_linked?`
  check filters anything that has since been ingested.

  The on-disk check matters because presence-without-a-link isn't
  unique to a transient failure — a title the user removed and deleted
  from disk leaves the same shape (a presence row, no `WatchedFile`)
  with nothing left to recover. Without it, a long-unrun reconciliation
  (e.g. after the ADR-023 startup race went unnoticed for a while) can
  resurrect a whole backlog of already-deleted titles in one pass.
  Skipped rows are left for `Library.AbsenceSweeper` to eventually purge.

  Returns `{:ok, count}` where `count` is the number of events emitted.
  """
  @spec rescan_unlinked() :: {:ok, non_neg_integer()}
  def rescan_unlinked do
    linked_paths = Library.Files.linked_paths_subquery()

    rows =
      Enum.filter(
        Repo.all(
          from p in FilePresence,
            where: p.file_path not in subquery(linked_paths),
            select: %{path: p.file_path, media_dir: p.media_dir}
        ),
        fn row -> File.exists?(row.path) end
      )

    Enum.each(rows, fn row ->
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.pipeline_input(),
        {:file_detected, %{path: row.path, media_dir: row.media_dir}}
      )
    end)

    count = length(rows)

    if count > 0 do
      Log.info(:watcher, "rescan_unlinked re-emitted #{count} stranded file_detected events")
    end

    {:ok, count}
  end

  @doc """
  Fire-and-forget `rescan_unlinked/0`. Runs on a supervised context-layer
  task so web-layer callers don't block and don't own the work — the
  re-emit must complete regardless of the triggering LiveView (ADR-049).
  """
  def rescan_unlinked_async do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, &rescan_unlinked/0)
    :ok
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
