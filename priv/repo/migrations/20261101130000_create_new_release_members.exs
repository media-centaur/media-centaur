defmodule MediaCentaur.Repo.Migrations.CreateNewReleaseMembers do
  @moduledoc """
  The New Releases shelf membership (campaign `discovery.md`, M9): the
  ordered TMDB movie ids that qualified at the last shelf refresh and the
  US digital release date each qualified with. Not a copy of the titles:
  everything drawn comes from the store's record (ADR-071). Rewritten
  whole by `MediaCentaur.NewReleases.replace/1`.
  """
  use Ecto.Migration

  def change do
    create table(:new_release_members, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :tmdb_id, :integer, null: false
      add :position, :integer, null: false
      add :digital_date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:new_release_members, [:tmdb_id])
    create index(:new_release_members, [:position])
  end
end
