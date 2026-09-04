defmodule MediaCentaur.Acquisition.Targets do
  @moduledoc """
  Target-row query + lifecycle operations sitting *between* the typed
  command surface (`Pursuits.Commands.*`) and the facade.

  `list_auto_targets/1` is a flat read filtered by lifecycle stage —
  used by the auto-acquisition admin UI to render the all-targets table
  without going through the per-pursuit aggregation that the main
  Downloads page uses.

  `rearm_target/1` and `cancel_target/2` flip a single target row in
  place — distinct from `Pursuits.Commands.ChangeTarget` (which pivots
  the *pursuit* to a freshly-inserted target row). The in-place
  operations are the right shape when the UI shows individual targets
  and a row-level affordance flips just that row.

  `cancel_active_targets_for/3` bulk-cancels every in-flight target on
  every pursuit matching a TMDB tuple — used by the Reactor when a
  tracked item is removed and the user has effectively withdrawn
  consent to keep chasing it.

  All operations broadcast a `MediaCentaur.Acquisition.TargetEvents`
  struct on `acquisition:updates`, so subscribers see the same typed
  event regardless of which entry point fired the flip.
  """

  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.Jobs.PursueTarget
  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, TargetUnit, Unit}
  alias MediaCentaur.Acquisition.{Target, TargetEvents, TargetStatus}
  alias MediaCentaur.Repo

  @doc """
  Lists `acquisition_targets` filtered by lifecycle stage.

  - `:all` — every row, newest-updated first
  - `:active` — `seeking` (the live job set)
  - `:failed` — terminal failure
  - `:cancelled` — explicitly cancelled
  - `:acquired` — release picked and submitted
  - `:succeeded` — file landed
  """
  @spec list_auto_targets(:all | :active | :failed | :cancelled | :acquired | :succeeded) ::
          [Target.t()]
  def list_auto_targets(filter \\ :all) do
    Target
    |> auto_targets_filter(filter)
    |> order_by([t], desc: t.updated_at)
    |> Repo.all()
  end

  @doc """
  Finds the `content_path` (the download client's reported save location,
  captured once by `DownloadIdentity` and never overwritten) that
  `file_path` falls under — an exact match for a single-file release, or
  an ancestor-directory match for a multi-file pack. `nil` when no target
  relates to it.

  Resolved fresh from the file's *current* path on every call rather than
  cached anywhere, so a later move can only ever make this stop matching
  (falling back to no folder boundary) — never falsely match the wrong
  folder. Used by `MediaCentaur.DeleteTargets` to find the exact footprint
  of a download, rather than guessing folder boundaries from disk layout.
  """
  @spec find_content_path_for(String.t()) :: String.t() | nil
  def find_content_path_for(file_path) do
    Target
    |> where([t], not is_nil(t.content_path))
    |> select([t], t.content_path)
    |> Repo.all()
    |> Enum.find(fn content_path ->
      file_path == content_path or String.starts_with?(file_path, content_path <> "/")
    end)
  end

  defp auto_targets_filter(query, :all), do: query

  defp auto_targets_filter(query, :active), do: where(query, [t], t.status in ^TargetStatus.in_flight())

  defp auto_targets_filter(query, status), do: where(query, [t], t.status == ^to_string(status))

  @doc """
  Re-arms a terminal target back to `seeking` and re-enqueues a
  `PursueTarget` Oban job. Resets `attempt_count` to 0 so the snooze
  schedule starts fresh. Broadcasts `%TargetEvents.Armed{}`.

  No-op for already-active targets (returns the target as-is). Use
  `Pursuits.Commands.ChangeTarget` when the pursuit's `current_target_id`
  should pivot to a freshly-inserted row — `rearm_target/1` flips this
  row in place.
  """
  @spec rearm_target(Ecto.UUID.t()) :: {:ok, Target.t()} | {:error, :not_found}
  def rearm_target(target_id) do
    case Repo.get(Target, target_id) do
      nil ->
        {:error, :not_found}

      %Target{} = target ->
        if TargetStatus.rearmable?(target.status) do
          {:ok, restart_target(target, "target re-armed")}
        else
          {:ok, target}
        end
    end
  end

  defp restart_target(%Target{} = target, log_label) do
    {:ok, restarted} =
      target
      |> Ecto.Changeset.change(
        status: "seeking",
        attempt_count: 0,
        acquired_at: nil,
        cancelled_at: nil,
        cancelled_reason: nil,
        last_attempt_outcome: nil
      )
      |> Repo.update()

    Oban.insert(PursueTarget.new(%{"target_id" => restarted.id}))
    Acquisition.broadcast_update(%TargetEvents.Armed{target: restarted})
    Log.info(:acquisition, "#{log_label} — #{restarted.title}")
    restarted
  end

  @doc """
  Cancels an active target (status `seeking`). No-op for terminal-state
  targets; broadcasts `%TargetEvents.Cancelled{}` only when the row
  was actually flipped.
  """
  @spec cancel_target(Ecto.UUID.t(), String.t()) ::
          {:ok, Target.t()} | {:error, :not_found}
  def cancel_target(target_id, reason) when is_binary(reason) do
    case Repo.get(Target, target_id) do
      nil ->
        {:error, :not_found}

      %Target{} = target ->
        if TargetStatus.in_flight?(target.status) do
          {:ok, cancelled} = Repo.update(Target.cancelled_changeset(target, reason))
          Acquisition.broadcast_update(%TargetEvents.Cancelled{target: cancelled})
          Log.info(:acquisition, "target cancelled — #{target.title} (#{reason})")
          {:ok, cancelled}
        else
          {:ok, target}
        end
    end
  end

  @doc """
  Torrent hashes of the pursuit's in-flight (cancellable-status)
  targets that have a captured download — the client items a pursuit
  cancellation must stop (campaign pursuit-identity-and-lifecycle:
  cancel must not mint orphans). Read *before* `close_in_flight_for/3`
  flips their status.
  """
  @spec in_flight_hashes(Ecto.UUID.t()) :: [String.t()]
  def in_flight_hashes(pursuit_id) when is_binary(pursuit_id) do
    Repo.all(
      from(t in Target,
        where:
          t.pursuit_id == ^pursuit_id and t.status in ^TargetStatus.cancellable() and
            not is_nil(t.torrent_hash),
        select: t.torrent_hash
      )
    )
  end

  @doc """
  Unit-scoped variant of `in_flight_hashes/1`: hashes of the
  in-flight targets *covering one unit* — what a pivot or swap
  abandons. Read before the command flips their status.
  """
  @spec in_flight_hashes_for_unit(Ecto.UUID.t()) :: [String.t()]
  def in_flight_hashes_for_unit(unit_id) when is_binary(unit_id) do
    covering = from(tu in TargetUnit, where: tu.unit_id == ^unit_id, select: tu.target_id)

    Repo.all(
      from(t in Target,
        where:
          t.id in subquery(covering) and t.status in ^TargetStatus.cancellable() and
            not is_nil(t.torrent_hash),
        select: t.torrent_hash
      )
    )
  end

  @doc """
  Closes every in-flight target for a pursuit at the moment the pursuit
  itself transitions to a terminal state.

  - `final_target_id` (optional, only meaningful for `Satisfy`) — the
    target that landed the file. Marked `succeeded`.
  - Every other target on the pursuit that is still
    `seeking` / `acquired` — marked `cancelled` with `cancel_reason`.

  Why this exists: snoozed `PursueTarget` Oban jobs survive across the
  pursuit's terminal transition. Without this cleanup, those jobs wake
  hours later, see a `seeking` target row on a satisfied pursuit, and
  grab a duplicate release. Cancelling the targets here turns the
  worker's existing target-status guard into a hard stop on its next
  wake — no Prowlarr call, no duplicate download.

  Idempotent: re-running on already-cancelled rows is a no-op `update_all`.

  No broadcasts. The pursuit's own terminal event (`PursuitSatisfied`,
  `PursuitExhausted`, `PursuitCancelled`) is what the UI listens for at
  the per-pursuit level; per-target cancellation broadcasts in this path
  would just duplicate that signal.
  """
  @spec close_in_flight_for(Ecto.UUID.t(), Ecto.UUID.t() | nil, String.t()) :: :ok
  def close_in_flight_for(pursuit_id, final_target_id, cancel_reason)
      when is_binary(pursuit_id) and is_binary(cancel_reason) do
    now = DateTime.utc_now(:second)

    if is_binary(final_target_id) do
      Repo.update_all(
        from(t in Target,
          where: t.pursuit_id == ^pursuit_id and t.id == ^final_target_id
        ),
        set: [status: "succeeded", next_attempt_at: nil, updated_at: now]
      )
    end

    cancel_query =
      from(t in Target,
        where: t.pursuit_id == ^pursuit_id and t.status in ^TargetStatus.cancellable()
      )

    cancel_query =
      case final_target_id do
        nil -> cancel_query
        id when is_binary(id) -> from(t in cancel_query, where: t.id != ^id)
      end

    Repo.update_all(cancel_query,
      set: [
        status: "cancelled",
        cancelled_at: now,
        cancelled_reason: cancel_reason,
        next_attempt_at: nil,
        updated_at: now
      ]
    )

    :ok
  end

  @doc """
  Cancels every active target whose pursuit matches `(tmdb_id, tmdb_type)`.
  Used by the `Reactor` when a tracked item is removed.

  The cancellation is one `update_all` regardless of how many targets
  match — broadcasts still fire per target so subscribers (LiveViews,
  decision-card refreshers) receive one `%TargetEvents.Cancelled{}` each.
  """
  @spec cancel_active_targets_for(String.t(), String.t(), String.t()) :: :ok
  def cancel_active_targets_for(tmdb_id, tmdb_type, reason) when is_binary(reason) do
    # Current targets live on the units (ADR-055) — one join query
    # collects every matching pursuit's unit-level current_target_id.
    target_ids =
      Repo.all(
        from(u in Unit,
          join: p in Pursuit,
          on: p.id == u.pursuit_id,
          where: p.recipe_type == "tmdb" and p.tmdb_id == ^tmdb_id and p.tmdb_type == ^tmdb_type,
          where: not is_nil(u.current_target_id),
          select: u.current_target_id
        )
      )

    case target_ids do
      [] ->
        :ok

      ids ->
        bulk_cancel_targets(ids, reason)
        :ok
    end
  end

  # Single SQL update for all in-flight targets, then per-target
  # broadcast off the returning rows so subscribers see the same shape
  # as the single-target `cancel_target/2` path.
  defp bulk_cancel_targets(target_ids, reason) do
    now = DateTime.utc_now(:second)

    {_count, updated} =
      Repo.update_all(
        from(t in Target,
          where: t.id in ^target_ids and t.status in ^TargetStatus.in_flight(),
          select: t
        ),
        set: [
          status: "cancelled",
          cancelled_at: now,
          cancelled_reason: reason,
          next_attempt_at: nil,
          updated_at: now
        ]
      )

    Enum.each(updated, fn %Target{} = target ->
      Acquisition.broadcast_update(%TargetEvents.Cancelled{target: target})
      Log.info(:acquisition, "target cancelled — #{target.title} (#{reason})")
    end)
  end
end
