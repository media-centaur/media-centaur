defmodule MediaCentarr.Repo.Migrations.AddDetailPanelFields do
  use Ecto.Migration

  def change do
    alter table(:library_movies) do
      add :tagline, :string
      add :original_language, :string
      add :studio, :string
      add :country_code, :string
      add :vote_count, :integer
    end

    alter table(:library_tv_series) do
      add :tagline, :string
      add :original_language, :string
      add :studio, :string
      add :country_code, :string
      add :vote_count, :integer
      add :network, :string
    end
  end
end
