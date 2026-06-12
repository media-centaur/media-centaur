defmodule MediaCentaur.Repo.DataMigrations.RenameWatchDirsSettingsKey do
  @moduledoc """
  Renames the Settings row `config:watch_dirs` to `config:media_dirs`,
  part of the repository-wide "watch directory" → "media directory"
  terminology change. The value (the media-dir entries list) is carried
  over unchanged.

  This file is **append-only**. Never edit a shipped data migration.

  Idempotent: the UPDATE only fires while the new key is absent, and
  the trailing DELETE clears a leftover legacy row in the (theoretical)
  case where both keys exist — the new key wins.
  """
  use Ecto.Migration

  @rename_legacy_key """
  UPDATE settings_entries SET key = 'config:media_dirs'
  WHERE key = 'config:watch_dirs'
    AND NOT EXISTS (SELECT 1 FROM settings_entries WHERE key = 'config:media_dirs')
  """

  @drop_leftover_legacy_key """
  DELETE FROM settings_entries WHERE key = 'config:watch_dirs'
  """

  def up, do: rename_key(repo())

  def down, do: :ok

  @doc """
  Rename body, exposed for direct testing. Idempotent — re-runs are
  no-ops once the new key exists.
  """
  def rename_key(repo) do
    repo.query!(@rename_legacy_key)
    repo.query!(@drop_leftover_legacy_key)
    :ok
  end
end
