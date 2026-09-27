defmodule MediaCentaur.Repo.Migrations.CreateProfiles do
  @moduledoc """
  One profile per known public key (ADR-073): what the key published
  about itself. `raw_event` keeps the signed wire form for republish;
  `created_at` is the wire time that decides which copy wins. A row
  exists only for the identity and roster members.
  """
  use Ecto.Migration

  def change do
    create table(:profiles, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :pubkey, :text, null: false
      add :name, :text
      add :raw_event, :map, null: false
      add :created_at, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:profiles, [:pubkey])
  end
end
