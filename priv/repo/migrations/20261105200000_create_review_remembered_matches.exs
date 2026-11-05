defmodule MediaCentaur.Repo.Migrations.CreateReviewRememberedMatches do
  @moduledoc """
  A person's answer in Review, kept for the name the files were read as
  (`Review.RememberedMatch`, campaign `review-bulk-match`). One row per
  name: the folded title, the type it is searched as and the year, with
  a missing year counted as its own value — hence the expression index,
  since SQLite treats NULLs in a plain unique index as distinct.
  """
  use Ecto.Migration

  def change do
    create table(:review_remembered_matches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title_form, :string, null: false
      add :media_type, :string, null: false
      add :parsed_year, :integer
      add :parsed_title, :string, null: false
      add :tmdb_id, :integer, null: false
      add :tmdb_type, :string, null: false
      add :match_title, :string
      add :match_year, :string
      add :match_poster_path, :string

      timestamps(type: :utc_datetime)
    end

    execute(
      "CREATE UNIQUE INDEX review_remembered_matches_name_index ON review_remembered_matches (title_form, media_type, ifnull(parsed_year, 0))",
      "DROP INDEX review_remembered_matches_name_index"
    )
  end
end
