defmodule MediaCentarr.Repo.Migrations.RenameIdentifiersToExternalIds do
  use Ecto.Migration

  def change do
    rename table(:library_identifiers), to: table(:library_external_ids)
    rename table(:library_external_ids), :property_id, to: :source
    rename table(:library_external_ids), :value, to: :external_id
  end
end
