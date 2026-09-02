defmodule MediaCentaur.Repo.Migrations.AddRelays do
  @moduledoc "The user's Nostr relay list. Connection state is runtime, never a column."
  use Ecto.Migration

  def change do
    create table(:relays, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :url, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:relays, [:url])
  end
end
