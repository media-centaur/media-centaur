defmodule MediaCentaur.Repo.DataMigrations.AwaitingFilesDropResolved do
  @moduledoc """
  Campaign `review-coherence` (2026-09-29): an episode-mapping awaiting
  file's `:resolved` status is gone. Confirming a mapping links the file
  and deletes its row, and a linked file is never listed, so rows already
  marked resolved have nothing left to hold and are deleted.

  This file is **append-only**. Never edit a shipped data migration.

  Raw SQL, snapshot-style: no live schema aliases. Idempotent — a second
  run finds no resolved rows.
  """
  use Ecto.Migration

  def up, do: sweep(repo())

  def down, do: :ok

  @doc "Deletes the awaiting rows marked resolved. Returns `:ok`."
  def sweep(repo) do
    repo.query!("DELETE FROM episode_mapping_awaiting_files WHERE status = 'resolved'", [])
    :ok
  end
end
