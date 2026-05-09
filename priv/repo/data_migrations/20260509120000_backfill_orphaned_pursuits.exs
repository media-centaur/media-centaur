defmodule MediaCentarr.Repo.DataMigrations.BackfillOrphanedPursuits do
  @moduledoc """
  Creates pursuits for in-flight grabs that predate the pursuit feature
  and lack a `pursuit_id`.

  Scope is limited to in-flight grabs (`searching` / `snoozed`). Terminal
  grabs (`grabbed`, `abandoned`, `cancelled`) are intentionally skipped —
  closing a synthetic pursuit would require fabricated terminal events
  that don't reflect what actually happened.

  This file is **append-only**. Never edit a shipped data migration —
  fix forward with a new one. The body uses raw SQL via `repo().query!/2`
  so it remains a snapshot, decoupled from live schema/context modules.
  """
  use Ecto.Migration

  @in_flight_statuses ["searching", "snoozed"]

  # The `IN (?, ?)` placeholder count must match `length(@in_flight_statuses)`.
  # Don't grow this list without also growing the SQL — and don't grow either
  # in this shipped migration. Append-only: a new in-flight status would ship
  # as a new data migration.
  @select_orphans """
  SELECT id, tmdb_id, tmdb_type, title, year, season_number, episode_number,
         origin, attempt_count, inserted_at
  FROM acquisition_grabs
  WHERE pursuit_id IS NULL AND status IN (?, ?)
  """

  @insert_pursuit """
  INSERT INTO acquisition_pursuits
    (id, state, origin, tmdb_id, tmdb_type, title, year, season_number,
     episode_number, criteria, tried_release_guids, attempt_count,
     inserted_at, updated_at)
  VALUES (?, 'active', ?, ?, ?, ?, ?, ?, ?, '{}', '[]', ?, ?, ?)
  """

  @insert_event """
  INSERT INTO acquisition_pursuit_events
    (id, pursuit_id, denormalized_pursuit_title, kind, payload,
     occurred_at, inserted_at, updated_at)
  VALUES (?, ?, ?, 'pursuit_started', ?, ?, ?, ?)
  """

  @link_grab "UPDATE acquisition_grabs SET pursuit_id = ? WHERE id = ?"

  def up, do: backfill(repo())

  def down, do: :ok

  @doc """
  Backfill body, exposed for direct testing. Idempotent: re-running is a
  no-op because the WHERE clause excludes grabs already linked to a pursuit.
  """
  def backfill(repo) do
    {:ok, %{rows: rows}} = repo.query(@select_orphans, @in_flight_statuses)
    Enum.each(rows, &backfill_one(repo, &1))
  end

  # The destructure order MUST match the SELECT column order in
  # `@select_orphans`. A column reorder there would silently misaligne this
  # destructure — no exception, just corrupt rows. If you copy this file as
  # a template for a new data migration, keep this comment.
  defp backfill_one(repo, [
         grab_id,
         tmdb_id,
         tmdb_type,
         title,
         year,
         season_number,
         episode_number,
         origin,
         attempt_count,
         grab_inserted_at
       ]) do
    pursuit_id = Ecto.UUID.generate()
    event_id = Ecto.UUID.generate()
    now = DateTime.utc_now(:second)
    origin = origin || "auto"
    occurred_at = grab_inserted_at || now
    payload_json = Jason.encode!(%{"origin" => origin})

    repo.query!(@insert_pursuit, [
      pursuit_id,
      origin,
      tmdb_id,
      tmdb_type,
      title,
      year,
      season_number,
      episode_number,
      attempt_count || 0,
      now,
      now
    ])

    repo.query!(@insert_event, [
      event_id,
      pursuit_id,
      title,
      payload_json,
      occurred_at,
      now,
      now
    ])

    repo.query!(@link_grab, [pursuit_id, grab_id])
  end
end
