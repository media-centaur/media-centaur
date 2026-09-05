defmodule MediaCentaur.Watcher.Rescan do
  @moduledoc """
  On-demand passes over the watched directories: a fresh scan for
  untracked video files, and the recovery re-emit for files the
  library knows are present but never linked. Both have `_async`
  forms for web-layer callers (ADR-049).
  """
  import Ecto.Query
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics
  alias MediaCentaur.Watcher.Supervisor

  @doc """
  Scans all watched directories for video files not yet tracked.
  Returns `{:ok, total_count}`.
  """
  def scan do
    results =
      Enum.map(Supervisor.watchers(), fn {_dir, pid} ->
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
      Topics.publish(
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
end
