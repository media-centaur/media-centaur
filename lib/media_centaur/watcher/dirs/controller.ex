defmodule MediaCentaur.Watcher.Dirs.Controller do
  @moduledoc """
  Keeps the running watchers and image-dir monitors equal to the configured
  media dirs: starts one watcher per `Config.get(:media_dirs)` entry and one
  monitor per image dir outside its media dir (`ImageCache.dirs_outside_media_dir/0`)
  in `init/1` — synchronously, so the watchers are up when
  `Watcher.Supervisor` has started — and reconciles both sets on every
  `{:config_updated, :media_dirs, _}`. A directory is its own identity: an
  edited path is a stop plus a start, a renamed entry keeps its watcher.

  Alive only while watching is on (`Watcher.Dirs`). The running sets are
  read back from the registries through `Watcher.Supervisor`; nothing is
  stored here.
  """
  use GenServer

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library.ImageCache
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Watcher
  alias MediaCentaur.Watcher.DirMonitor
  alias MediaCentaur.Watcher.Reconciler

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc false
  # Test-only sync point: any prior `:config_updated` message in this
  # process's mailbox is guaranteed processed before the call returns.
  @spec __sync_for_test__() :: :ok
  def __sync_for_test__, do: GenServer.call(__MODULE__, :__sync_for_test__)

  @impl true
  def init(nil) do
    :ok = Config.subscribe()
    Enum.each(Config.get(:media_dirs) || [], &start_dir/1)
    Enum.each(ImageCache.dirs_outside_media_dir(), &start_image_monitor/1)
    {:ok, nil}
  end

  @impl true
  def handle_info({:config_updated, :media_dirs, entries}, state) do
    reconcile_dirs(entries)
    reconcile_image_monitors()
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_call(:__sync_for_test__, _from, state), do: {:reply, :ok, state}

  # --- watchers ---------------------------------------------------------

  defp reconcile_dirs(new_entries) do
    old_entries = for {dir, _pid} <- Watcher.Supervisor.watchers(), do: entry(dir)
    actions = Reconciler.diff(old_entries, Enum.map(new_entries, &entry(&1["dir"])))

    Enum.each(actions.to_stop, &stop_dir/1)
    Enum.each(actions.to_start, fn new -> start_dir(new["dir"]) end)

    Log.info(:watcher, "reconcile — start=#{length(actions.to_start)} stop=#{length(actions.to_stop)}")
  end

  defp entry(dir), do: %{"id" => dir, "dir" => dir, "images_dir" => nil, "name" => nil}

  defp start_dir(dir),
    do: start_under(MediaCentaur.Watcher.DynamicSupervisor, {Watcher, dir}, "watcher", dir)

  defp stop_dir(dir) do
    case Registry.lookup(MediaCentaur.Watcher.Registry, dir) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(MediaCentaur.Watcher.DynamicSupervisor, pid)
      [] -> :ok
    end
  end

  # --- image-dir monitors -----------------------------------------------

  defp reconcile_image_monitors do
    actions = Reconciler.diff_image_monitors(running_image_pairs(), ImageCache.dirs_outside_media_dir())

    Enum.each(actions.to_stop, &stop_image_monitor/1)
    Enum.each(actions.to_start, &start_image_monitor/1)

    if actions.to_start != [] or actions.to_stop != [] do
      Log.info(
        :watcher,
        "reconcile image monitors — start=#{length(actions.to_start)} stop=#{length(actions.to_stop)}"
      )
    end
  end

  defp running_image_pairs do
    Enum.flat_map(Watcher.Supervisor.image_monitors(), fn {image_dir, pid} ->
      try do
        [{DirMonitor.media_dir(pid), image_dir}]
      catch
        :exit, _ -> []
      end
    end)
  end

  defp start_image_monitor({media_dir, image_dir}) do
    start_under(
      MediaCentaur.Watcher.DirMonitor.DynamicSupervisor,
      {DirMonitor, {image_dir, media_dir}},
      "image dir monitor",
      image_dir
    )
  end

  defp stop_image_monitor(image_dir) do
    case Registry.lookup(MediaCentaur.Watcher.DirMonitor.Registry, image_dir) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(MediaCentaur.Watcher.DirMonitor.DynamicSupervisor, pid)

      [] ->
        :ok
    end
  end

  # `kind` labels the log line; `name` is the directory.
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
end
