defmodule MediaCentaur.Repo.Migrations.CreateReconciliationAwaitingFiles do
  use Ecto.Migration

  def change do
    create table(:reconciliation_awaiting_files, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :file_path, :string, null: false
      add :media_dir, :string, null: false
      add :tmdb_id, :integer, null: false
      add :series_title, :string
      add :claimed_season, :integer
      add :claimed_episode, :integer
      add :claimed_title, :string
      add :status, :string, null: false, default: "pending"
      timestamps()
    end

    # One awaiting record per file — re-discovery upserts rather than dups.
    create unique_index(:reconciliation_awaiting_files, [:file_path])
    # The review surface lists the pending queue grouped by show.
    create index(:reconciliation_awaiting_files, [:tmdb_id, :status])
  end
end
