defmodule MediaCentaur.Repo.Migrations.ProfilesCarryAHue do
  @moduledoc "A profile's hue, an integer 0–359 (UIDR-048), nil when the key published none. A plain add the outgoing release never reads."
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :hue, :integer
    end
  end
end
