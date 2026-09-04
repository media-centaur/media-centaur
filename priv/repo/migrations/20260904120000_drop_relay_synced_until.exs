defmodule MediaCentaur.Repo.Migrations.DropRelaySyncedUntil do
  use Ecto.Migration

  @moduledoc """
  Drops the relay sync cursor. Every connect now reads the relay from the
  start (`Recommendations.Sync`): a relay holds one record per signer per
  title, so the history is one page, and a `since` cursor skipped events
  published late with an older stamp. Nothing to backfill — the column
  was derived state.
  """

  def change do
    alter table(:relays) do
      remove :synced_until, :integer
    end
  end
end
