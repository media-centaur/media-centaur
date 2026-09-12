defmodule MediaCentaur.Repo.Migrations.ReviewReplacesRecommendation do
  @moduledoc """
  A review (kind 32164) replaces the recommendation (kind 32160) as the
  activity a person states on purpose (ADR-068). Its words are `text`
  rather than `note`, and its `sentiment` — dislike, like or love — is
  optional: nil means the review gives no verdict, and nil on every
  other kind's row. The column was not-null with a default of `like`
  that the other kinds carried without reading; SQLite has no `ALTER
  COLUMN`, so it is dropped and added back nullable without a default.
  Nothing is lost: every row that carried a sentiment is a
  recommendation, and the data migration that ships with this release
  (`ReviewReplacesRecommendation` under `priv/repo/data_migrations/`)
  removes those rows.

  The `kind` column keeps its `"recommendation"` default from
  `GeneralizeRecommendationsToActivities`: dropping a default is a
  table rebuild in SQLite, and the changeset always sets `kind`, so
  the default is never read. Accepted (campaign
  `review-replaces-recommendation`, incoherence 4).
  """
  use Ecto.Migration

  def change do
    rename table(:activities), :note, to: :text

    alter table(:activities) do
      remove :sentiment, :text, null: false, default: "like"
    end

    alter table(:activities) do
      add :sentiment, :text
    end
  end
end
