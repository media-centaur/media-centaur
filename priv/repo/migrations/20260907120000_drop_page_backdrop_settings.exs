defmodule MediaCentaur.Repo.Migrations.DropPageBackdropSettings do
  use Ecto.Migration

  # The per-page backdrop toggles are gone: Home's hero is the only surface
  # that carries page artwork, so `library_backdrop` / `incoming_backdrop`
  # have no reader left and their rows are orphans. Delete them rather than
  # leaving keys in the settings table that nothing can explain.
  #
  # Idempotent (a DELETE that matches nothing is a no-op), so it is safe on a
  # fresh install, on one that never touched the toggles, and on one seeded
  # by `SeedBackdropDefaultsForExistingInstalls`.

  @keys ["library_backdrop", "incoming_backdrop"]

  def up do
    execute(fn ->
      for key <- @keys do
        repo().query!("DELETE FROM settings_entries WHERE key = ?", [key])
      end
    end)
  end

  # Nothing reads these keys any more, so there is nothing to restore.
  def down, do: :ok
end
