defmodule MediaCentarr.Watcher.AbsencePolicy do
  @moduledoc """
  Owns the lifecycle decision for absent watcher files: when an
  `:absent` `KnownFile` becomes a deletion candidate, what to do when
  a watch dir flips between available and unavailable, and the
  broadcast contract for `{:files_removed, paths}` on
  `MediaCentarr.Topics.library_file_events()`.

  Uses `MediaCentarr.Watcher.FilePresence` for the data primitives
  (record / mark / restore / reset / query). The relationship is
  one-way: this module names FilePresence; FilePresence is unaware of
  the policy. Same shape as `MediaCentarr.Library.Availability` ↔
  `MediaCentarr.WatcherStatus` — consumer + data source.

  ## Durability invariant

  TTL purge **only** acts on files whose `watch_dir` is currently
  `:watching` or `:initializing` per
  `MediaCentarr.Watcher.Supervisor.statuses/0`. A file marked absent
  while its drive is unavailable is *unverifiable*, not *deleted*, and
  must never be destroyed — destroying it would cascade through
  `MediaCentarr.Library.FileEventHandler` to entity rows on a drive we
  cannot currently see.

  ## Remount fairness

  When a watch dir transitions back to `:available`, the absence clock
  for every `:absent` file in that dir is reset to `now()`. This gives
  the user a guaranteed full TTL window from the moment the drive
  becomes visible — covering the case where a drive was offline for
  longer than the TTL period and then comes back. `restore_present_files/2`
  (called by the watcher on its first scan after remount) clears
  `absent_since` for files actually found on disk; the reset here is
  the *floor* for files that remain missing.

  ## Custom Credo guard

  The destructive query in `purge_expired/1` is the canonical example
  the `MediaCentarr.Credo.Checks.DestructiveFileQuery` (MC0015) static
  check enforces — it expects every `Repo.delete_all` on file/entity
  tables to filter on `:watch_dir` (or carry an explicit override
  comment).

  ## Testability

  `purge_expired/1` accepts the available-dirs list as a parameter so
  tests drive the policy decision directly without `:sys.*` or
  `GenServer.call` from outside the module (per ADR-026). The
  `:ttl_check` GenServer handler calls
  `purge_expired(available_watch_dirs())` to use live watcher state.
  """
  use GenServer
  require MediaCentarr.Log, as: Log
  import Ecto.Query

  alias MediaCentarr.{Config, Repo}
  alias MediaCentarr.Watcher.{FilePresence, KnownFile}

  @ttl_check_interval :timer.hours(24)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # --- Public read API ---

  @doc """
  Per-watch-dir summary of files at risk of TTL purge, regardless of
  whether the dir is currently available. Returned shape:

      %{watch_dir => %{file_count: non_neg_integer(), earliest_absent_since: DateTime.t()}}

  Pure DB read — no GenServer round-trip. The status-page formatter
  joins this against the live availability map to decide what to
  render (and only renders rows for currently-`:unavailable` dirs).
  """
  @spec at_risk_summary() :: %{
          String.t() => %{file_count: non_neg_integer(), earliest_absent_since: DateTime.t()}
        }
  def at_risk_summary do
    Map.new(
      Repo.all(
        from(k in KnownFile,
          where: k.state == :absent,
          group_by: k.watch_dir,
          select: {k.watch_dir, %{file_count: count(k.id), earliest_absent_since: min(k.absent_since)}}
        )
      )
    )
  end

  @doc """
  Returns the list of watch dirs currently in `:watching` or
  `:initializing` state — the only dirs whose files may be considered
  for TTL purge. Public so tests can compose the policy decision and
  so the MC0015 Credo check has a discoverable name to recognise as
  the availability helper.
  """
  @spec available_watch_dirs() :: [String.t()]
  def available_watch_dirs do
    for %{dir: dir, state: state} <- MediaCentarr.Watcher.Supervisor.statuses(),
        state in [:watching, :initializing],
        do: dir
  end

  @doc """
  Runs the TTL purge against the supplied set of available watch
  dirs. The destructive query — by construction — only touches files
  whose `watch_dir` appears in `available_dirs`, so a file marked
  absent while its drive is unavailable can never be destroyed.

  Returns `{count, paths}` for the rows deleted. Emits the
  `[:media_centarr, :watcher, :absence_policy, :purge]` telemetry
  event and broadcasts `{:files_removed, paths}` on the library
  file-events topic when one or more rows are deleted.
  """
  @spec purge_expired([String.t()]) :: {non_neg_integer(), [String.t()]}
  def purge_expired(available_dirs) when is_list(available_dirs) do
    ttl_days = Config.get(:file_absence_ttl_days) || 30
    cutoff = DateTime.add(DateTime.utc_now(), -ttl_days, :day)

    expired =
      if available_dirs == [] do
        []
      else
        Repo.all(
          from(k in KnownFile,
            where:
              k.state == :absent and
                k.absent_since < ^cutoff and
                k.watch_dir in ^available_dirs,
            select: k.file_path
          )
        )
      end

    if expired != [] do
      Log.warning(
        :watcher,
        "TTL purge — #{length(expired)} files (drives confirmed available)"
      )

      # Availability already enforced by the `where` clause above (the
      # selection of `expired` requires `k.watch_dir in ^available_dirs`);
      # this statement narrows by file_path within that already-filtered
      # set, so the destructive op is safe without its own watch_dir clause.
      # credo:disable-for-next-line MediaCentarr.Credo.Checks.DestructiveFileQuery
      Repo.delete_all(from(k in KnownFile, where: k.file_path in ^expired))

      :telemetry.execute(
        [:media_centarr, :watcher, :absence_policy, :purge],
        %{count: length(expired)},
        %{paths: expired, available_dirs: available_dirs}
      )

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.library_file_events(),
        {:files_removed, expired}
      )
    end

    {length(expired), expired}
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
  def handle_info({:dir_state_changed, dir, :watch_dir, :unavailable}, state) do
    Log.info(:watcher, "marked files absent — drive unavailable for #{dir}")

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      FilePresence.mark_absent_for_watch_dir(dir)
    end)

    {:noreply, state}
  end

  def handle_info({:dir_state_changed, dir, :watch_dir, :available}, state) do
    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      case FilePresence.reset_absence_clock_for_dir(dir) do
        0 -> :ok
        n -> Log.info(:watcher, "absence clock reset — #{n} files in #{dir}")
      end
    end)

    {:noreply, state}
  end

  def handle_info({:dir_state_changed, _dir, _role, _state}, state) do
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
end
