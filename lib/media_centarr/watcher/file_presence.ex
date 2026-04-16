defmodule MediaCentarr.Watcher.FilePresence do
  @moduledoc """
  Tracks file presence on the filesystem via the `watcher_files` table.

  Two responsibilities:
  - **Presence tracking**: records which files the watcher has seen, marks
    them absent when drives disconnect, restores them when drives return.
  - **TTL expiration**: periodically checks for files that have been absent
    longer than the configured TTL and triggers library cleanup.

  Subscribes to PubSub for watcher state changes (drive unavailable).
  """
  use GenServer
  require MediaCentarr.Log, as: Log
  import Ecto.Query

  alias MediaCentarr.{Config, Repo}
  alias MediaCentarr.Watcher.KnownFile

  @ttl_check_interval :timer.hours(24)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Records a newly detected file as present in watcher_files.
  Upserts: if the file already exists (e.g., was absent), restores it to present.
  """
  @spec record_file(String.t(), String.t()) :: :ok
  def record_file(file_path, watch_dir) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(KnownFile, file_path: file_path) do
      nil ->
        KnownFile.record_changeset(%{file_path: file_path, watch_dir: watch_dir})
        |> Repo.insert!()

      existing ->
        existing
        |> Ecto.Changeset.change(state: :present, absent_since: nil, updated_at: now)
        |> Repo.update!()
    end

    :ok
  end

  @doc """
  Returns a MapSet of all known file paths for the given watch directory.
  Used by the watcher scan to skip already-detected files.
  """
  @spec known_file_paths(String.t()) :: MapSet.t()
  def known_file_paths(watch_dir) do
    from(k in KnownFile,
      where: k.watch_dir == ^watch_dir,
      select: k.file_path
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Restores absent files that are now present on disk.
  Returns the list of restored file paths (caller can look up entity IDs).
  """
  @spec restore_present_files(String.t(), [String.t()]) :: [String.t()]
  def restore_present_files(_watch_dir, []), do: []

  def restore_present_files(watch_dir, existing_paths) do
    existing_set = MapSet.new(existing_paths)

    absent_files =
      from(k in KnownFile,
        where: k.watch_dir == ^watch_dir and k.state == :absent
      )
      |> Repo.all()

    restored =
      Enum.filter(absent_files, fn file ->
        MapSet.member?(existing_set, file.file_path)
      end)

    if restored != [] do
      Log.info(:watcher, "restored #{length(restored)} absent files — #{watch_dir}")

      ids = Enum.map(restored, & &1.id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(k in KnownFile, where: k.id in ^ids)
      |> Repo.update_all(set: [state: :present, absent_since: nil, updated_at: now])
    end

    Enum.map(restored, & &1.file_path)
  end

  @doc """
  Marks all present files for the given watch directory as absent.
  Called when a drive becomes unavailable.
  """
  @spec mark_absent_for_watch_dir(String.t()) :: :ok
  def mark_absent_for_watch_dir(watch_dir) do
    now = DateTime.utc_now()

    from(k in KnownFile,
      where: k.watch_dir == ^watch_dir and k.state == :present
    )
    |> Repo.update_all(set: [state: :absent, absent_since: now, updated_at: now])

    :ok
  end

  @doc """
  Marks specific file paths as absent. Called when file deletion is detected.
  """
  @spec mark_files_absent([String.t()]) :: :ok
  def mark_files_absent([]), do: :ok

  def mark_files_absent(file_paths) do
    now = DateTime.utc_now()

    from(k in KnownFile, where: k.file_path in ^file_paths)
    |> Repo.update_all(set: [state: :absent, absent_since: now, updated_at: now])

    :ok
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.dir_state())
    schedule_ttl_check()
    {:ok, %{}, {:continue, :initial_ttl_check}}
  end

  @impl true
  def handle_continue(:initial_ttl_check, state) do
    check_ttl_expirations()
    {:noreply, state}
  end

  @impl true
  def handle_info({:dir_state_changed, dir, :watch_dir, :unavailable}, state) do
    Log.info(:watcher, "marked files absent — drive unavailable for #{dir}")

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      mark_absent_for_watch_dir(dir)
    end)

    {:noreply, state}
  end

  def handle_info({:dir_state_changed, _dir, _role, _state}, state) do
    {:noreply, state}
  end

  def handle_info(:ttl_check, state) do
    check_ttl_expirations()
    schedule_ttl_check()
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # TTL expiration
  # ---------------------------------------------------------------------------

  defp check_ttl_expirations do
    ttl_days = Config.get(:file_absence_ttl_days) || 30
    cutoff = DateTime.add(DateTime.utc_now(), -ttl_days, :day)

    expired =
      from(k in KnownFile,
        where: k.state == :absent and k.absent_since < ^cutoff,
        select: k.file_path
      )
      |> Repo.all()

    if expired != [] do
      Log.info(:watcher, "TTL expired — #{length(expired)} absent files")

      # Delete expired records from watcher_files
      from(k in KnownFile, where: k.file_path in ^expired)
      |> Repo.delete_all()

      # Broadcast for Library to clean up its records
      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.library_file_events(),
        {:files_removed, expired}
      )
    end
  end

  defp schedule_ttl_check do
    Process.send_after(self(), :ttl_check, @ttl_check_interval)
  end
end
