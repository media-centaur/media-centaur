defmodule MediaCentarr.Repo.Migrations.CollapseNeedsDecisionIntoAwaitingFlag do
  @moduledoc """
  Collapses `state = "needs_decision"` into an orthogonal
  `awaiting_decision_at` timestamp on `acquisition_pursuits`.

  Per the pursuits-maturation campaign (audit Finding 2):
  `needs_decision` was a substate of `active` — the pursuit is still
  in flight, just blocked on user input. Encoding that as a peer
  state conflated "where in the lifecycle" with "what is the system
  waiting on". This migration separates the two: state stays as
  `active | satisfied | exhausted | cancelled`; `awaiting_decision_at`
  records when (and whether) user input is pending.

  Backfill: every row with `state = "needs_decision"` is rewritten to
  `state = "active"` with `awaiting_decision_at = updated_at`.
  """

  use Ecto.Migration

  def up do
    alter table(:acquisition_pursuits) do
      add :awaiting_decision_at, :utc_datetime
    end

    flush()

    execute("""
    UPDATE acquisition_pursuits
       SET awaiting_decision_at = updated_at,
           state = 'active'
     WHERE state = 'needs_decision'
    """)
  end

  def down do
    execute("""
    UPDATE acquisition_pursuits
       SET state = 'needs_decision'
     WHERE awaiting_decision_at IS NOT NULL
       AND state = 'active'
    """)

    alter table(:acquisition_pursuits) do
      remove :awaiting_decision_at
    end
  end
end
