defmodule MediaCentarr.Library.AbsenceSweeper do
  @moduledoc """
  TTL-driven cleanup of stale `Library.FilePresence` rows. Replaces
  `MediaCentarr.Watcher.AbsencePolicy` as the owner of the
  "this file has been absent for long enough — assume real deletion"
  decision.

  ## Decision

  A `FilePresence` row whose `last_seen_at` is older than the
  configured TTL (`:file_absence_ttl_days`, default 30) AND whose
  `watch_dir` is currently `:watching` / `:initializing` per
  `MediaCentarr.WatcherStatus.statuses/0` is a deletion candidate.
  The two conditions together encode ADR-045's durability
  invariant: a file on an offline drive is *unverifiable*, not
  *deleted*, and must never be destroyed.

  On purge, the row is deleted from `library_file_presences` and
  the FK cascade (`on_delete: :delete_all` from Phase 3) removes
  the dependent `WatchedFile` / `ExtraFile`. The
  `{:files_removed, paths}` broadcast on
  `MediaCentarr.Topics.library_file_events()` is preserved
  byte-for-byte from `Watcher.AbsencePolicy` so
  `Library.FileEventHandler` consumes it unchanged.

  ## Remount fairness

  When a watch dir transitions back to `:available`, every
  `FilePresence` row in that dir gets `last_seen_at` reset to
  `now()`. The watcher's first scan after remount re-stamps
  present files (no-op refresh — same timestamp), so the reset
  only matters for files that remain missing — they get a full
  TTL window before purge.

  ## Testability

  `purge_expired/1` takes the available-dirs list as a parameter
  so tests drive the policy directly without GenServer round-trips
  (ADR-026). The `:ttl_check` handler calls
  `purge_expired(available_watch_dirs())` to use live watcher
  state.
  """
  use GenServer
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Config
  alias MediaCentarr.Library.FileEventHandler
  alias MediaCentarr.Library.FilePresence
  alias MediaCentarr.Library.Helpers

  @ttl_check_interval :timer.hours(24)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # --- Public read API ---

  @doc """
  Per-watch-dir summary of files at risk of TTL purge, regardless
  of whether the dir is currently available. Used by the status
  page to render an "at-risk" callout for unavailable dirs.

  Pure DB read — no GenServer round-trip.
  """
  @spec at_risk_summary() :: %{
          String.t() => %{file_count: non_neg_integer(), earliest_absent_since: DateTime.t()}
        }
  defdelegate at_risk_summary, to: FilePresence

  @doc """
  Returns the list of watch dirs currently in `:watching` or
  `:initializing` state — the only dirs whose files may be
  considered for TTL purge. Public so tests can compose the
  policy decision.
  """
  @spec available_watch_dirs() :: [String.t()]
  def available_watch_dirs do
    for %{dir: dir, state: state} <- MediaCentarr.WatcherStatus.statuses(),
        state in [:watching, :initializing],
        do: dir
  end

  @doc """
  Runs the TTL purge against the supplied set of available watch
  dirs. The destructive query — by construction — only touches
  files whose `watch_dir` appears in `available_dirs`, so a file
  whose drive is unavailable can never be destroyed.

  Returns `{count, paths}` for the rows deleted. Emits the
  `[:media_centarr, :library, :absence_sweeper, :purge]`
  telemetry event and broadcasts `{:files_removed, paths}` on
  `library_file_events()` when one or more rows are deleted.

  Cascade-delete via the Phase-3 FK then removes
  `WatchedFile` / `ExtraFile` rows.
  """
  @spec purge_expired([String.t()]) :: {non_neg_integer(), [String.t()]}
  def purge_expired(available_dirs) when is_list(available_dirs) do
    cutoff = absent_cutoff()

    expired_paths =
      if available_dirs == [] do
        []
      else
        expired_paths_under(cutoff, available_dirs)
      end

    if expired_paths != [] do
      Log.warning(
        :library,
        "TTL purge — #{length(expired_paths)} files (drives confirmed available)"
      )

      # Run entity cleanup BEFORE deleting FilePresence — the
      # Phase-3 FK cascade would otherwise remove WatchedFile / ExtraFile
      # ahead of `FileEventHandler.cleanup_removed_files/1`, leaving no
      # seed for the entity-cascade traversal.
      entity_ids = FileEventHandler.cleanup_removed_files(expired_paths)

      # Cascade-delete is a no-op now (dependent rows already deleted
      # by cleanup_removed_files); this leaves the presence row itself
      # gone so the next scan re-stamps if the file reappears.
      FilePresence.delete_paths(expired_paths)

      Helpers.broadcast_entities_changed(entity_ids)

      :telemetry.execute(
        [:media_centarr, :library, :absence_sweeper, :purge],
        %{count: length(expired_paths)},
        %{paths: expired_paths, available_dirs: available_dirs}
      )

      # Broadcast contract preserved verbatim from
      # Watcher.AbsencePolicy — downstream subscribers (currently
      # FileEventHandler, which idempotently re-processes; future
      # subscribers might be metrics aggregators) see the same event
      # shape regardless of trigger.
      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.library_file_events(),
        {:files_removed, expired_paths}
      )
    end

    {length(expired_paths), expired_paths}
  end

  # --- GenServer ---

  @impl true
  def init(_) do
    :ok = Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.dir_state())
    schedule_ttl_check()
    {:ok, %{}, {:continue, :initial_ttl_check}}
  end

  @impl true
  def handle_continue(:initial_ttl_check, state) do
    purge_expired(available_watch_dirs())
    {:noreply, state}
  end

  @impl true
  def handle_info({:dir_state_changed, dir, :watch_dir, :available}, state) do
    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      case FilePresence.reset_last_seen_for_dir(dir) do
        0 -> :ok
        n -> Log.info(:library, "presence clock reset — #{n} files in #{dir}")
      end
    end)

    {:noreply, state}
  end

  # Drive going `:unavailable` is a no-op: presence rows for that dir
  # simply stop having their `last_seen_at` refreshed, and the
  # `available_dirs` filter in `purge_expired/1` excludes the dir
  # from any future deletion run until it's back.
  def handle_info({:dir_state_changed, _dir, _role, _state_value}, state) do
    {:noreply, state}
  end

  def handle_info(:ttl_check, state) do
    purge_expired(available_watch_dirs())
    schedule_ttl_check()
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp schedule_ttl_check do
    Process.send_after(self(), :ttl_check, @ttl_check_interval)
  end

  defp absent_cutoff do
    ttl_days = Config.get(:file_absence_ttl_days) || 30
    DateTime.add(DateTime.utc_now(), -ttl_days, :day)
  end

  defp expired_paths_under(cutoff, available_dirs) do
    import Ecto.Query

    MediaCentarr.Repo.all(
      from(p in FilePresence,
        where: p.last_seen_at < ^cutoff and p.watch_dir in ^available_dirs,
        select: p.file_path
      )
    )
  end
end
