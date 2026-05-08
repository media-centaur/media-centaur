defmodule MediaCentarr.DataMigrations do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Runner for one-shot data migrations that live under
  `priv/repo/data_migrations/`.

  Data migrations are distinct from schema migrations: they fix up rows
  rather than tables, and they may be too slow or too domain-shaped to
  belong in a schema-migration boot sequence. They use the same
  `Ecto.Migration` machinery, but tracked in a separate
  `data_migrations` table so the two streams progress independently.

  ## Authoring rules

  - **Use raw SQL via `repo().query!/2` or the `execute/1` macro.** Never
    alias live schema or context modules — a migration is a snapshot,
    and live code rots out from under it.
  - **Idempotent at the row level.** `Ecto.Migrator` only guarantees
    each migration runs to completion once on success — if the body
    crashes halfway, the entire body re-runs. Use WHERE clauses that
    skip already-processed rows (e.g. `WHERE pursuit_id IS NULL`).
  - **Append-only.** Never edit a shipped data migration. Fix forward
    with a new file.
  - **Sync only.** The runner runs everything inline. For long or
    external-API-driven backfills, the migration should INSERT directly
    into `oban_jobs` (raw SQL, snapshot-style) — the running app picks
    those up after boot. Don't try to perform the work inside the
    migration body.

  See `decisions/architecture/2026-05-09-040-data-migrations.md`.
  """

  @app :media_centarr

  @doc """
  Runs every pending data migration against `repo`. Assumes the repo is
  already started — for release-boot use, go through
  `MediaCentarr.Release.migrate_data/0`, which wraps this in
  `Ecto.Migrator.with_repo/2`.
  """
  @spec run!(module()) :: [integer()]
  def run!(repo) do
    Ecto.Migrator.run(repo, path(), :up,
      all: true,
      migration_source: "data_migrations"
    )
  end

  @doc "Filesystem path to the data-migrations directory inside the app."
  @spec path() :: String.t()
  def path do
    Application.app_dir(@app, "priv/repo/data_migrations")
  end
end
