defmodule MediaCentaur.Application.DatabaseUpgrade do
  @moduledoc """
  Brings the database up to this code's version at application start
  (`MediaCentaur.Release.migrate/0`), as a child of the application
  supervisor directly before the Repo: every process that reads the
  database starts after its schema and data migrations have all run. A
  child spec whose start does the work and returns `:ignore`, so the
  tree's start order is the sequencing.

  It runs before the Repo, not through it, so the application's start
  and the installer upgrade a database the same way: the migrator's own
  repo with one connection, stopped when the upgrade is done. A new
  database migrated through the application's pool failed part way on
  2026-11-14 — the pool's connections race to switch the file to WAL
  (see `MediaCentaur.Release`).

  A migration or snapshot that fails raises here and the application does
  not start: serving a database a migration left half way is the one
  outcome this child exists to rule out.

  Not listed under `:test`: the suite migrates its database before it
  starts.
  """

  @doc false
  def child_spec(_opts), do: %{id: __MODULE__, start: {__MODULE__, :run, []}, restart: :temporary}

  @doc "Runs the upgrade and returns `:ignore` — there is no process to supervise."
  @spec run() :: :ignore
  def run do
    :ok = MediaCentaur.Release.migrate()
    :ignore
  end
end
