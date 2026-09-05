defmodule MediaCentaur.Watcher.Supervisor do
  @moduledoc """
  Coordinates multiple `MediaCentaur.Watcher` instances, one per watched directory.

  Starts a `DynamicSupervisor` and a `Registry`, then launches one Watcher child
  per directory from `Config.get(:media_dirs)`.
  """
  use Supervisor
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Settings.Config

  alias MediaCentaur.Library.ImageCache
  alias MediaCentaur.Topics
  alias MediaCentaur.Watcher.DirMonitor

  # Whether watching is on — flipped by `start_watchers/0` / `stop_watchers/0`
  # (boot and the Settings toggle). `running?/0` cannot stand in for it:
  # "on with no media dirs yet" and "off" both have zero children, and only
  # the former should react when the first dir is added.
  @enabled_key {__MODULE__, :enabled?}

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
  Starts added directories and terminates removed ones. A directory is
  its own identity here, so an edited path is a stop plus a start.

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

    Enum.each(actions.to_start, fn new -> start_dir(new["dir"]) end)

    count_summary =
      "start=#{length(actions.to_start)} stop=#{length(actions.to_stop)}"

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
  # here so `statuses/0`, `watchers/0`, and `image_dir_statuses/0` don't have
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
    Topics.subscribe(MediaCentaur.Topics.dir_state())
  end

  @doc """
  Turns watching on and launches a watcher for each configured directory.
  Called at boot and from the Settings toggle; while on, media-dir edits
  reconcile the running set (`Watcher.ConfigListener`).
  """
  def start_watchers do
    :persistent_term.put(@enabled_key, true)
    dirs = Config.get(:media_dirs) || []

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
    pairs = ImageCache.dirs_outside_media_dir()
    Enum.each(pairs, &start_image_monitor/1)
  end

  @doc """
  Reconciles running image-dir monitors with the desired set computed
  from `ImageCache.dirs_outside_media_dir/0`. Called by
  `Watcher.ConfigListener` whenever media_dirs change so that editing
  `images_dir` on a watch entry takes effect without an app restart.
  """
  @spec reconcile_image_dir_monitors() :: :ok
  def reconcile_image_dir_monitors do
    actions =
      MediaCentaur.Watcher.Reconciler.diff_image_monitors(
        currently_running_image_pairs(),
        ImageCache.dirs_outside_media_dir()
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
      resume? = enabled?()
      stop_watchers()

      try do
        fun.()
      after
        if resume?, do: start_watchers()
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

  @doc "Every running watcher as `{media_dir, pid}`."
  @spec watchers() :: [{String.t(), pid()}]
  def watchers, do: registered_pids(MediaCentaur.Watcher.Registry)

  @doc "Returns true if any watcher children are currently running."
  def running? do
    DynamicSupervisor.which_children(MediaCentaur.Watcher.DynamicSupervisor) != []
  end

  @doc "Whether watching is on (`start_watchers/0` since the last `stop_watchers/0`)."
  @spec enabled?() :: boolean()
  def enabled?, do: :persistent_term.get(@enabled_key, false)

  @doc "Turns watching off and stops all running watcher children."
  def stop_watchers do
    :persistent_term.put(@enabled_key, false)

    MediaCentaur.Watcher.DynamicSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(MediaCentaur.Watcher.DynamicSupervisor, pid)
    end)
  end
end
