defmodule MediaCentaur.Repo.DataMigrations.RenameShowWatchlistSettingsKey do
  @moduledoc """
  Renames the Settings row `show_watchlist` to `show_discovery`: the
  Watchlist page became the Discovery page (watchlist tab now; feed and
  friends tabs next), and the preference that gates its sidebar entry
  follows. The value (`%{"enabled" => boolean}`) is carried over unchanged.

  This file is **append-only**. Never edit a shipped data migration.

  Idempotent: the UPDATE only fires while the new key is absent, and the
  trailing DELETE clears a leftover legacy row in the (theoretical) case
  where both keys exist — the new key wins.
  """
  use Ecto.Migration

  @rename_legacy_key """
  UPDATE settings_entries SET key = 'show_discovery'
  WHERE key = 'show_watchlist'
    AND NOT EXISTS (SELECT 1 FROM settings_entries WHERE key = 'show_discovery')
  """

  @drop_leftover_legacy_key """
  DELETE FROM settings_entries WHERE key = 'show_watchlist'
  """

  def up, do: rename_key(repo())

  def down, do: :ok

  @doc "Rename body, exposed for direct testing. Idempotent."
  def rename_key(repo) do
    repo.query!(@rename_legacy_key)
    repo.query!(@drop_leftover_legacy_key)
    :ok
  end
end
