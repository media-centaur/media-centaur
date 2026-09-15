defmodule MediaCentaur.Watcher.Rescan do
  @moduledoc """
  On-demand passes over the watched directories: a fresh scan for
  untracked video files, the recovery re-emit for files the library
  knows are present but never linked, and the retraction that
  reconciles recorded state with the ignore rules. Each has an
  `_async` form for web-layer callers (ADR-049).
  """
  import Ecto.Query
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Library
  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics
  alias MediaCentaur.Watcher.IgnoreRules
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
  row that has no library link, still exists on disk, and is still
  library content per `Watcher.IgnoreRules`.

  Recovery hook for stranded files — Discovery can drop a message when
  a downstream service (TMDB, network) fails transiently, and PubSub
  has no replay. Calling this after the underlying problem is resolved
  (e.g. the user updates an invalid TMDB API key) feeds those files
  back into the pipeline. Idempotent: Discovery's `already_linked?`
  check filters anything that has since been ingested.

  The ignore-rule check is the same `library_content?/2` call the
  inotify filter and the scan make. A presence row can outlive the
  rules that admitted it — a row recorded before the user excluded its
  directory is still in the table, and without this check every boot
  re-fed it to the pipeline, costing a parse and two TMDB searches per
  file that could never resolve. The scan can't catch these: it never
  walks an ignored directory, so it never sees them to retract.

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

    unlinked =
      Repo.all(
        from p in FilePresence,
          where: p.file_path not in subquery(linked_paths),
          select: %{path: p.file_path, media_dir: p.media_dir}
      )

    rules_by_media_dir =
      unlinked
      |> Enum.map(& &1.media_dir)
      |> Enum.uniq()
      |> Map.new(fn media_dir -> {media_dir, IgnoreRules.load(media_dir)} end)

    # Admission first: an in-memory predicate ahead of a syscall per row.
    rows =
      Enum.filter(unlinked, fn row ->
        IgnoreRules.library_content?(row.path, Map.fetch!(rules_by_media_dir, row.media_dir)) and
          File.exists?(row.path)
      end)

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

  @doc """
  Reconciles recorded state with the ignore rules: every
  `Library.FilePresence` row a rule now covers is retracted.

  An ignore rule states that a subtree is not library content, so a row
  claiming otherwise has to go. The scan cannot do this — it never
  walks an ignored directory, so it never sees the rows to retract —
  and without it a rule added after the fact only filtered future work:
  the rows stayed, `rescan_unlinked/0` re-fed them to the pipeline on
  every boot, and their review-queue entries sat there for files the
  user had already said were not library content.

  Retraction goes out as `{:files_removed, paths}` on
  `Topics.library_file_events()` — the one representation of "the
  library no longer has these paths", already consumed by
  `Library.FileEventHandler` (which clears the presence rows) and
  `Review.FileEventHandler` (which clears the queue rows). The files
  themselves are untouched on disk.

  An **imported** file under a rule is reported, never retracted.
  `Watcher.IgnoreRules`' invariant forbids that state and Settings
  rejects such a rule, so a row showing it can only pre-date the
  guard; retracting it would destroy a library entry for a file still
  on disk.

  Returns `{:ok, count}` of paths retracted.
  """
  @spec retract_ignored() :: {:ok, non_neg_integer()}
  def retract_ignored do
    rows = Repo.all(from(p in FilePresence, select: %{path: p.file_path, media_dir: p.media_dir}))

    rules_by_media_dir =
      rows
      |> Enum.map(& &1.media_dir)
      |> Enum.uniq()
      |> Map.new(fn media_dir -> {media_dir, IgnoreRules.load(media_dir)} end)

    covered =
      Enum.flat_map(rows, fn row ->
        rules = Map.fetch!(rules_by_media_dir, row.media_dir)

        case IgnoreRules.matching_rule(row.path, rules) do
          nil -> []
          rule -> [{row.path, rule}]
        end
      end)

    linked = Library.Files.linked_paths(Enum.map(covered, &elem(&1, 0)))
    {imported, retractable} = Enum.split_with(covered, &MapSet.member?(linked, elem(&1, 0)))

    Enum.each(imported, fn {path, rule} ->
      Log.warning(
        :watcher,
        "#{path} is imported but sits under #{IgnoreRules.describe_rule(rule)} — " <>
          "left alone; remove the rule or remove the title from your library"
      )
    end)

    retract(Enum.map(retractable, &elem(&1, 0)))
  end

  defp retract([]), do: {:ok, 0}

  defp retract(paths) do
    Log.info(:watcher, "retracted #{length(paths)} path(s) now covered by an ignore rule")
    Topics.publish(Topics.library_file_events(), {:files_removed, paths})
    {:ok, length(paths)}
  end

  @doc """
  Fire-and-forget `retract_ignored/0`, on a supervised context-layer
  task so web-layer callers don't own the work (ADR-049).
  """
  def retract_ignored_async do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, &retract_ignored/0)
    :ok
  end

  @doc """
  The startup reconciliation pass (ADR-023), in order: retract what the
  ignore rules no longer admit, scan for untracked files, then re-emit
  what is still stranded.

  One named operation rather than a caller composing the three, so the
  order and the meaning of "reconcile" live with the passes themselves.
  Retraction goes first so the scan and the re-emit work against a
  table that already matches the rules; the ordering is advisory rather
  than load-bearing, since retraction's removal travels by broadcast
  and `rescan_unlinked/0` applies the same rules itself.

  Returns `{:ok, %{retracted: n, scanned: n, reemitted: n}}`.
  """
  @spec reconcile() ::
          {:ok,
           %{retracted: non_neg_integer(), scanned: non_neg_integer(), reemitted: non_neg_integer()}}
  def reconcile do
    {:ok, retracted} = retract_ignored()
    {:ok, scanned} = scan()
    {:ok, reemitted} = rescan_unlinked()

    {:ok, %{retracted: retracted, scanned: scanned, reemitted: reemitted}}
  end
end
