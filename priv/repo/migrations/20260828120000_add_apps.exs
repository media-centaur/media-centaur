defmodule MediaCentaur.Repo.Migrations.AddApps do
  use Ecto.Migration

  def change do
    create table(:apps, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :command, :text, null: false
      add :origin, :map, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
