defmodule MediaCentarr.Watcher.FilePresence do
  @moduledoc """
  Data primitives over `MediaCentarr.Watcher.KnownFile`.

  Records files the watcher has seen, marks them absent when they
  disappear or their drive disconnects, restores them when they're
  back on disk, resets the absence clock on remount. Pure data
  operations — no timers, no policy decisions, no PubSub.

  Lifecycle policy (TTL expiration, dir-state event handling, the
  `{:files_removed, paths}` broadcast contract) lives in
  `MediaCentarr.Watcher.AbsencePolicy`. The relationship is one-way:
  AbsencePolicy uses these primitives; this module is unaware of the
  policy.
  """
  require MediaCentarr.Log, as: Log
  import Ecto.Query

  alias MediaCentarr.Repo
  alias MediaCentarr.Watcher.KnownFile

  @doc """
  Records a newly detected file as present in watcher_files.
  Upserts atomically: if the row already exists (e.g., was absent), restores it
  to present. Single SQL statement — safe under concurrent callers.
  """
  @spec record_file(String.t(), String.t()) :: :ok
  def record_file(file_path, watch_dir) do
    now = DateTime.utc_now(:second)

    Repo.insert!(
      KnownFile.record_changeset(%{file_path: file_path, watch_dir: watch_dir}),
      on_conflict: [set: [state: :present, absent_since: nil, updated_at: now]],
      conflict_target: :file_path
    )

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
      Repo.all(from(k in KnownFile, where: k.watch_dir == ^watch_dir and k.state == :absent))

    restored =
      Enum.filter(absent_files, fn file ->
        MapSet.member?(existing_set, file.file_path)
      end)

    if restored != [] do
      Log.info(:watcher, "restored #{length(restored)} absent files — #{watch_dir}")

      ids = Enum.map(restored, & &1.id)
      now = DateTime.utc_now(:second)

      Repo.update_all(from(k in KnownFile, where: k.id in ^ids),
        set: [state: :present, absent_since: nil, updated_at: now]
      )
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

    Repo.update_all(
      from(k in KnownFile, where: k.watch_dir == ^watch_dir and k.state == :present),
      set: [state: :absent, absent_since: now, updated_at: now]
    )

    :ok
  end

  @doc """
  Marks specific file paths as absent. Called when file deletion is detected.
  """
  @spec mark_files_absent([String.t()]) :: :ok
  def mark_files_absent([]), do: :ok

  def mark_files_absent(file_paths) do
    now = DateTime.utc_now()

    Repo.update_all(from(k in KnownFile, where: k.file_path in ^file_paths),
      set: [state: :absent, absent_since: now, updated_at: now]
    )

    :ok
  end

  @doc """
  Resets `absent_since` to `now()` for every `:absent` row in the
  given watch dir. Returns the number of rows touched.

  Called by `MediaCentarr.Watcher.AbsencePolicy` on a dir's
  `:available` transition so users get a guaranteed full TTL window
  from the moment the drive becomes visible again, instead of
  counting absence accumulated while the drive was unverifiable.
  Files actually found on the next scan are then restored to
  `:present` (with `absent_since: nil`) by `restore_present_files/2`;
  this reset only matters for files that remain missing.
  """
  @spec reset_absence_clock_for_dir(String.t()) :: non_neg_integer()
  def reset_absence_clock_for_dir(watch_dir) do
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(k in KnownFile, where: k.watch_dir == ^watch_dir and k.state == :absent),
        set: [absent_since: now, updated_at: now]
      )

    count
  end
end
