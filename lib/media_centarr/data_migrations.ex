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
  - **Idempotent at the row level.** `Ecto.Migrator` wraps `up/0` in a
    transaction by default, so a crash mid-body rolls back cleanly and
    the next run starts from a pristine state. Row-level idempotency
    (e.g. `WHERE pursuit_id IS NULL`) is what protects (a) re-running
    after success when something else needs the migration replayed, and
    (b) future migrations that set `@disable_ddl_transaction true` to
    commit in batches.
  - **No load-time side effects.** Migration files are loaded at suite
    startup by `test_helper.exs` so unit tests can reference each
    migration's helper functions directly. Top-level `Application.put_env`,
    `:on_load`, network calls, or filesystem writes will pollute the
    test environment. Keep `up/0` and any helpers as the only behavior
    surface; never run code at module-load time.
  - **Position-coupled SQL needs a comment.** When the body uses raw
    `SELECT col_a, col_b, ...` followed by an Elixir destructure of
    `[col_a, col_b, ...]`, leave a comment naming the coupling — a
    future column reorder in the SELECT will silently misaligne the
    destructure. See `BackfillOrphanedPursuits` for the canonical
    template.
  - **Append-only.** Never edit a shipped data migration's behavior.
    Fix forward with a new file. Comment-only edits to a shipped
    migration are acceptable when they preserve the SQL and Elixir
    body byte-for-byte.
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
