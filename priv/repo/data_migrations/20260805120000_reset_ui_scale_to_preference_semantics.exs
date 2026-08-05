defmodule MediaCentaur.Repo.DataMigrations.ResetUiScaleToPreferenceSemantics do
  use Ecto.Migration

  # The `ui_scale` setting changed meaning. It used to be the whole scale —
  # users hand-picked e.g. 200% to correct for an unscaled 4K screen. Density
  # correction is now automatic (`--auto-scale` = screen width over the 1920px
  # reference, computed client-side in root.html.heex), and the setting became
  # a preference multiplier on top where 1.0 means "as designed". A surviving
  # legacy value would compound with the automatic factor (2.0 stored × 2.0
  # auto = 4×), so reset any existing row to 1.0 — the automatic factor
  # reproduces the size the legacy value was correcting for. Idempotent at the
  # row level: re-running rewrites 1.0 to 1.0.
  def up do
    execute("""
    UPDATE settings_entries SET value = '{"scale":1.0}' WHERE key = 'ui_scale'
    """)
  end

  def down, do: :ok
end
