defmodule MediaCentaur.Repo.Migrations.CreatePlayers do
  @moduledoc """
  One row per paired player: a device on the LAN admitted to this install
  by pairing (`campaigns/remote-players.md`, M1). The row's id is what
  the device's browser session holds; removing the row cuts it off.
  """
  use Ecto.Migration

  def change do
    create table(:players, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
