defmodule MediaCentaur.Repo.DataMigrations.DedupeSignalEvents do
  @moduledoc """
  Collapses historical duplicate signal events. Per-unit emission
  multiplied each `download_started` / `health_changed` by the
  pursuit's unit count — a 38-episode season pack wrote 38 identical
  rows per transition, all sharing (pursuit, kind, payload,
  occurred_at). Keep one row per group; decision/user events are never
  touched.

  This file is **append-only**. Never edit a shipped data migration.

  Idempotent: re-running deletes nothing further — every group already
  has exactly one surviving row. Irreversible by design: the duplicates
  carry no information (same payload, same timestamp) and recreating
  them would only restore a UI bug.
  """
  use Ecto.Migration

  @dedupe """
  DELETE FROM acquisition_pursuit_events
  WHERE kind IN ('download_started', 'health_changed')
    AND id NOT IN (
      SELECT MIN(id)
      FROM acquisition_pursuit_events
      WHERE kind IN ('download_started', 'health_changed')
      GROUP BY pursuit_id, kind, payload, occurred_at
    )
  """

  def up, do: dedupe(repo())

  def down, do: :ok

  @doc "Dedupe body, exposed for direct testing. Idempotent."
  def dedupe(repo) do
    repo.query!(@dedupe)
    :ok
  end
end
