defmodule MediaCentaur.Repo.Migrations.AddRelaySyncedUntil do
  @moduledoc "Per-relay sync cursor: the newest event time seen from that relay, so a reconnect asks only for what is newer."
  use Ecto.Migration

  def change do
    alter table(:relays) do
      add :synced_until, :integer
    end
  end
end
