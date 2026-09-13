defmodule MediaCentaur.Repo.DataMigrations.QualityPolicyLosesFloorAndPatience do
  @moduledoc """
  [UIDR-041] §6: the automatic quality policy keeps a highest resolution
  and a within-resolution preference and nothing else. The configurable
  floor (`auto_grab.default_min_quality`) and the 4K patience window
  (`auto_grab.4k_patience_hours`) are retired, and a title's download
  params keep only the lower-quality acceptance (`min_quality`): the
  per-title maximum and patience keys are stripped, and a row left with
  nothing to say is removed (an absent row and an empty one already
  meant the same thing).

  This file is **append-only**. Never edit a shipped data migration.

  Raw SQL, snapshot-style: no live schema aliases. Idempotent — a second
  run finds nothing to delete or strip.

  [UIDR-041]: `decisions/user-interface/2026-09-13-041-settings-cards-are-readouts-with-actions.md`
  """
  use Ecto.Migration

  @drop_settings "DELETE FROM settings_entries WHERE key IN ('auto_grab.default_min_quality', 'auto_grab.4k_patience_hours')"
  @strip_keys "UPDATE title_download_params SET params = json_remove(params, '$.max_quality', '$.quality_4k_patience_hours')"
  @drop_empty "DELETE FROM title_download_params WHERE json_extract(params, '$.min_quality') IS NULL"

  def up, do: sweep(repo())

  def down, do: :ok

  @doc """
  Deletes the two retired settings rows, strips the retired per-title
  keys, and removes rows left with nothing to say. Returns `:ok`.
  """
  def sweep(repo) do
    repo.query!(@drop_settings, [])
    repo.query!(@strip_keys, [])
    repo.query!(@drop_empty, [])
    :ok
  end
end
