defmodule MediaCentaur.Repo.Migrations.RenameReconciliationToEpisodeMapping do
  @moduledoc """
  The `Reconciliation` context is named `EpisodeMapping` (ADR-075). The
  table follows, and its indexes are recreated under the new table's
  default names so `unique_constraint(:file_path)` still maps the error.
  """
  use Ecto.Migration

  def change do
    drop unique_index(:reconciliation_awaiting_files, [:file_path])
    drop index(:reconciliation_awaiting_files, [:tmdb_id, :status])

    rename table(:reconciliation_awaiting_files), to: table(:episode_mapping_awaiting_files)

    create unique_index(:episode_mapping_awaiting_files, [:file_path])
    create index(:episode_mapping_awaiting_files, [:tmdb_id, :status])
  end
end
