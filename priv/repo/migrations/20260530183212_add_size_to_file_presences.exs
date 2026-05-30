defmodule MediaCentaur.Repo.Migrations.AddSizeToFilePresences do
  use Ecto.Migration

  # Byte size of the file on disk, captured at detection. Used by
  # relink-on-move to recognise a moved file (same relative-path + size)
  # and re-point the existing entity instead of orphaning it. Nullable:
  # rows written before this column exists keep `nil` and fall back to a
  # relative-path-only match on their first move (see `Library.MoveMatcher`).
  def change do
    alter table(:library_file_presences) do
      add :size, :integer
    end
  end
end
