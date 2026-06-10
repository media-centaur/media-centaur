defmodule MediaCentaur.Repo.DataMigrations.SupersedeLegacySeekers do
  @moduledoc """
  The ADR-056 cutover (release-tracking-plan-convergence Phase 2):
  system-cancels legacy auto-armed pursuits that are pure seekers —
  armed by the old Reactor→Arm path, still searching, nothing found —
  so their units stop claiming wants and the drop→plan pipeline takes
  over on the next sweep tick.

  Conservative by design (campaign Q8): a pursuit is superseded only
  when it is an `active` tmdb pursuit with origin `auto` and

    * NO target in `acquired` (a download in progress keeps running),
    * NO unit awaiting a user decision,
    * NO satisfied unit (mixed-outcome pursuits are left alone).

  Everything else completes under the existing machinery; its units
  keep claiming, and the want closes by library arrival as usual.

  The cancel reason is `superseded_by_plans` — distinct from user
  cancels on purpose: the want ledger treats user cancels as
  dismissals, while superseded seekers' wants stay OPEN (the ledger
  sweep opens them from current calendar state; the next tick re-plans
  them through the corpus/planner).

  Raw SQL per the data-migration authoring rules; no events are
  recorded for these cancels (acceptable for a one-shot migration —
  the targets carry the reason string). Idempotent: every UPDATE is
  gated on the current state, and a superseded pursuit no longer
  matches the selection.

  This file is **append-only**. Never edit a shipped data migration.
  """
  use Ecto.Migration

  def up, do: supersede(repo())
  def down, do: :ok

  def supersede(repo) do
    %{rows: rows} =
      repo.query!("""
      SELECT p.id
      FROM acquisition_pursuits p
      WHERE p.state = 'active'
        AND p.recipe_type = 'tmdb'
        AND p.origin = 'auto'
        AND NOT EXISTS (
          SELECT 1 FROM acquisition_targets t
          WHERE t.pursuit_id = p.id AND t.status = 'acquired'
        )
        AND NOT EXISTS (
          SELECT 1 FROM acquisition_pursuit_units u
          WHERE u.pursuit_id = p.id AND u.awaiting_decision_at IS NOT NULL
        )
        AND NOT EXISTS (
          SELECT 1 FROM acquisition_pursuit_units u
          WHERE u.pursuit_id = p.id AND u.state = 'satisfied'
        )
      """)

    Enum.each(rows, fn [pursuit_id] ->
      now = DateTime.to_iso8601(DateTime.utc_now(:second))

      repo.query!(
        """
        UPDATE acquisition_targets
        SET status = 'cancelled', cancelled_at = ?, cancelled_reason = 'superseded_by_plans'
        WHERE pursuit_id = ? AND status = 'seeking'
        """,
        [now, pursuit_id]
      )

      repo.query!(
        """
        UPDATE acquisition_pursuit_units
        SET state = 'cancelled'
        WHERE pursuit_id = ? AND state = 'active'
        """,
        [pursuit_id]
      )

      repo.query!(
        """
        UPDATE acquisition_pursuits
        SET state = 'cancelled'
        WHERE id = ? AND state = 'active'
        """,
        [pursuit_id]
      )
    end)

    :ok
  end
end
