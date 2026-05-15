defmodule MediaCentarr.Repo.Migrations.MovieSeriesMetadataSymmetry do
  @moduledoc """
  Brings `library_movie_series` to metadata parity with `library_tv_series`
  so the detail surface can render collections with the same shape as
  series. See Phase 1 Task 4 of the Library Schema v2 campaign
  (`campaigns/library-schema-v2.md`).

  Adds the missing scalars (`tagline`, `original_language`, `studio`,
  `country_code`, `vote_count`, `status`) and the JSON-backed
  `cast`/`crew` columns that back `embeds_many` of `Library.Person`. All
  columns are nullable — existing rows are valid as-is and will be
  enriched on next ingest / refresh.
  """
  use Ecto.Migration

  def change do
    alter table(:library_movie_series) do
      add :tagline, :string
      add :original_language, :string
      add :studio, :string
      add :country_code, :string
      add :vote_count, :integer
      add :status, :string
      add :cast, :map
      add :crew, :map
    end
  end
end
