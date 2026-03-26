defmodule MediaCentaur.Repo.Migrations.AddImageQueue do
  use Ecto.Migration

  def change do
    create table(:pipeline_image_queue, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :owner_id, :text, null: false
      add :owner_type, :text, null: false
      add :role, :text, null: false
      add :source_url, :text, null: false
      add :entity_id, :text, null: false
      add :watch_dir, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :retry_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pipeline_image_queue, [:owner_id, :role])
    create index(:pipeline_image_queue, [:status])
    create index(:pipeline_image_queue, [:entity_id])

    alter table(:library_images) do
      remove :url, :text
    end
  end
end
