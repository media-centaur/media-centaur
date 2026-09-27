defmodule MediaCentaur.Repo.Migrations.ProfilesCarryAnAvatarType do
  @moduledoc "A profile's avatar type (`image/webp`, `image/jpeg`, `image/png`), nil when the key published none; the file's path derives from the key and the type (`Social.AvatarStore`)."
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :avatar_type, :text
    end
  end
end
