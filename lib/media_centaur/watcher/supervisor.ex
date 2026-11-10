defmodule MediaCentaur.Watcher.Supervisor do
  @moduledoc """
  The watcher subsystem's supervisor and its operational facade.

  Tree, `:rest_for_one`:

    1. `Watcher.ScanStats` — the retained per-dir scan summaries;
    2. `Watcher.Registry` and `Watcher.DirMonitor.Registry` — always
       present, so the reads below answer `[]` while watching is off;
    3. `Watcher.IgnoreRulesListener` — not gated on watching;
    4. `MediaCentaur.Watcher.FlagSupervisor` — the `start_watchers` flag's
       children, `Watcher.Dirs` (the per-dir watchers, the image-dir
       monitors and the controller that keeps them equal to the configured
       media dirs). Started here, synchronously, when the flag is on, so
       the pipeline's startup recovery that follows in the application tree
       finds them.

  The flag (`Settings.Services.start?(:start_watchers)`) is the one owner of
  "watching is on"; `running?/0` is the tree's answer, read from the
  FlagSupervisor, never stored. `set_enabled/1` is what the Settings toggle
  does; `suspend/1` stops the watchers around a destructive operation.
  Aggregate reads (`statuses/0`, `watchers/0`, `image_dir_statuses/0`,
  `scan_stats/0`) go through the registries.
  """
  use Supervisor

  alias MediaCentaur.FlagSupervisor
  alias MediaCentaur.Settings
  alias MediaCentaur.Settings.Services
  alias MediaCentaur.Topics
  alias MediaCentaur.Watcher.DirMonitor

  @flag :start_watchers
  @flag_supervisor MediaCentaur.Watcher.FlagSupervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    flag_key = Services.key(@flag)

    children = [
      MediaCentaur.Watcher.ScanStats,
      {Registry, keys: :unique, name: MediaCentaur.Watcher.Registry},
      {Registry, keys: :unique, name: MediaCentaur.Watcher.DirMonitor.Registry},
      MediaCentaur.Watcher.IgnoreRulesListener,
      {FlagSupervisor,
       name: @flag_supervisor,
       flag: fn -> Services.start?(@flag) end,
       subscribe: &Settings.subscribe/0,
       relevant?: &match?({:setting_changed, ^flag_key, _value}, &1),
       children: [MediaCentaur.Watcher.Dirs],
       label: "the watchers",
       component: :watcher}
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 60)
  end

  @doc "Subscribe the caller to watcher directory state change events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(MediaCentaur.Topics.dir_state())
  end

  @doc """
  Turns watching on or off now and for every later boot: persists the start
  flag (`Settings.Services`) and reconciles the flag's children at once.
  What the Settings toggle does.
  """
  @spec set_enabled(boolean()) :: :ok
  def set_enabled(enabled?) when is_boolean(enabled?) do
    Services.set(@flag, enabled?)
    FlagSupervisor.reconcile(@flag_supervisor)
  end

  @doc "Whether watching is on: the flag's children are running."
  @spec running?() :: boolean()
  def running?, do: FlagSupervisor.running?(@flag_supervisor)

  @doc """
  Stops the watchers, runs `fun`, then reads the flag again — so a
  destructive operation (clearing the database) is not re-detected as it
  runs. The watchers come back even when `fun` raises.
  """
  @spec suspend((-> result)) :: result when result: term()
  def suspend(fun) when is_function(fun, 0), do: FlagSupervisor.suspend(@flag_supervisor, fun)

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
  `MediaCentaur.WatcherStatus`, by `Library.MediaFileAvailability`); the rest drive the
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
  Returns a list of `%{dir: path, media_dir: path, state: atom}` for all running DirMonitors.
  """
  def image_dir_statuses do
    image_monitors()
    |> Enum.flat_map(fn {dir, pid} ->
      try do
        [%{dir: dir, media_dir: DirMonitor.media_dir(pid), state: DirMonitor.status(pid)}]
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

  @doc "Every running image-dir monitor as `{image_dir, pid}`."
  @spec image_monitors() :: [{String.t(), pid()}]
  def image_monitors, do: registered_pids(DirMonitor.Registry)

  # Match-spec returning every {key, pid} pair from a Registry, named once.
  defp registered_pids(registry) do
    Registry.select(registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end
end
