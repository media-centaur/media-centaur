defmodule MediaCentaur.Repo.Migrations.AddFriends do
  @moduledoc "The roster of followed public keys. The nickname is local to this install."
  use Ecto.Migration

  def change do
    create table(:friends, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :pubkey, :text, null: false
      add :nickname, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:friends, [:pubkey])
  end
end
