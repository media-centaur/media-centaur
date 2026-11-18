defmodule MediaCentaur.Repo.DataMigrations.ServiceFlagsLoseEnvironment do
  @moduledoc """
  ADR-084 (2026-11-18): one instance owns a database, so a service start
  flag is no longer namespaced by the environment. `services:<env>:<service>`
  becomes `services:<service>`.

  The running environment's rows are the flags in force, so they keep
  their values under the new key. Another environment's rows are dropped,
  not carried over: this instance never read them, and carrying one would
  change what it runs.

  This file is **append-only**. Never edit a shipped data migration.

  Raw SQL, snapshot-style: no live schema aliases. Idempotent — a second
  run finds no environment-scoped rows. A key that somehow already exists
  unscoped wins over the scoped row.
  """
  use Ecto.Migration

  def up,
    do: drop_environment(repo(), to_string(Application.get_env(:media_centaur, :environment, :dev)))

  def down, do: :ok

  @doc "Moves `environment`'s flags to unscoped keys and drops every scoped flag. Returns `:ok`."
  def drop_environment(repo, environment) do
    prefix = "services:#{environment}:"

    repo.query!(
      """
      UPDATE settings_entries AS scoped
      SET key = 'services:' || substr(scoped.key, length(?1) + 1)
      WHERE scoped.key LIKE ?1 || '%'
        AND NOT EXISTS (
          SELECT 1 FROM settings_entries AS unscoped
          WHERE unscoped.key = 'services:' || substr(scoped.key, length(?1) + 1)
        )
      """,
      [prefix]
    )

    repo.query!("DELETE FROM settings_entries WHERE key LIKE 'services:%:%'", [])
    :ok
  end
end
