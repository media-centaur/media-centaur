defmodule MediaCentaur.Repo.Migrations.SeedBackdropDefaultsForExistingInstalls do
  use Ecto.Migration

  # The per-page backdrop flags (`library_backdrop`, `incoming_backdrop`)
  # flipped from default-on to default-off. An install that predates the
  # flip and never touched the toggles has no settings row, so the read
  # fallback alone would silently turn its backdrops off. Seed an explicit
  # `enabled: true` row for each missing key — but only on databases that
  # already have settings (a fresh install's settings table is empty at
  # migration time, and fresh installs must get the new default-off).
  # Idempotent: keys that already have a row are left untouched.

  @keys ["library_backdrop", "incoming_backdrop"]

  def up do
    execute(fn ->
      %{rows: [[settings_count]]} =
        repo().query!("SELECT COUNT(*) FROM settings_entries")

      if settings_count > 0 do
        now = DateTime.to_iso8601(DateTime.utc_now(:second))

        for key <- @keys do
          repo().query!(
            """
            INSERT INTO settings_entries (id, key, value, inserted_at, updated_at)
            SELECT ?, ?, ?, ?, ?
            WHERE NOT EXISTS (SELECT 1 FROM settings_entries WHERE key = ?)
            """,
            [Ecto.UUID.generate(), key, ~s({"enabled":true}), now, now, key]
          )
        end
      end
    end)
  end

  # The seeded rows are indistinguishable from user-set toggles, so
  # rolling back keeps them — harmless either way.
  def down, do: :ok
end
