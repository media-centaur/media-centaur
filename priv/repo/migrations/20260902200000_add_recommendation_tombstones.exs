defmodule MediaCentaur.Repo.Migrations.AddRecommendationTombstones do
  @moduledoc "A withdrawn recommendation stays as a tombstone: when it was deleted and the signed deletion event, so a stale copy from a relay cannot revive it and the deletion can be republished."
  use Ecto.Migration

  def change do
    alter table(:recommendations) do
      add :deleted_at, :utc_datetime
      add :deletion_event, :map
    end
  end
end
