defmodule MediaCentaur.Repo.DataMigrations.TrackingIsTwoSwitches do
  @moduledoc """
  Spec 2026-09-14 (UIDR-042): the ladder loses its `ask` and `default`
  rungs. A per-title grab policy no longer exists — Grab plans the
  release, and the person's planning mode says whether the plan asks
  first — so `ask` becomes `grab`. `default` followed the global
  auto-grab setting, which is deleted here too: a title at `default`
  becomes `grab`, unless that setting was Notify only (`"off"`), in which
  case the title only ever kept a calendar and becomes `follow`.

  This file is **append-only**. Never edit a shipped data migration.

  Raw SQL, snapshot-style: no live schema aliases. Idempotent — a second
  run finds no `ask` or `default` rows and no setting to delete.
  """
  use Ecto.Migration

  @setting_key "auto_grab.default_mode"
  @notify_only "off"

  def up, do: sweep(repo())

  # `grab` and `follow` were legal rungs before this migration, and an
  # absent setting reads as the old built-in default (Grab it).
  def down, do: :ok

  @doc "Folds the retired rungs and deletes the retired setting. Returns `:ok`."
  def sweep(repo) do
    default_rung =
      case repo.query!(
             "SELECT json_extract(value, '$.value') FROM settings_entries WHERE key = ?",
             [@setting_key]
           ) do
        %{rows: [[@notify_only]]} -> "follow"
        _grab_ask_or_absent -> "grab"
      end

    repo.query!("UPDATE title_intents SET rung = 'grab' WHERE rung = 'ask'", [])
    repo.query!("UPDATE title_intents SET rung = ? WHERE rung = 'default'", [default_rung])
    repo.query!("DELETE FROM settings_entries WHERE key = ?", [@setting_key])
    :ok
  end
end
