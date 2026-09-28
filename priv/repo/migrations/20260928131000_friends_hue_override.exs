defmodule MediaCentaur.Repo.Migrations.FriendsHueOverride do
  @moduledoc "The reader's hue for a friend, an integer 0–359 masking the published one (UIDR-048); nil is none. A plain add."
  use Ecto.Migration

  def change do
    alter table(:friends) do
      add :hue_override, :integer
    end
  end
end
