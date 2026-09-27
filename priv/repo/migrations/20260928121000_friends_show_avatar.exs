defmodule MediaCentaur.Repo.Migrations.FriendsShowAvatar do
  @moduledoc "The reader's per-friend switch for the friend's avatar, on by default (UIDR-047)."
  use Ecto.Migration

  def change do
    alter table(:friends) do
      add :show_avatar, :boolean, null: false, default: true
    end
  end
end
