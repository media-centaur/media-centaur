defmodule MediaCentaur.Repo.Migrations.AddActivitySentiment do
  @moduledoc """
  A recommendation carries a sentiment — `like` or `love` — shown as the
  recommendation pennant. Every row already stored is a recommendation
  made before the field existed, and the wire contract reads an absent
  sentiment as `like`, so the column defaults to it; the other kinds'
  rows hold the default and never read it.
  """
  use Ecto.Migration

  def change do
    alter table(:activities) do
      add :sentiment, :text, null: false, default: "like"
    end
  end
end
