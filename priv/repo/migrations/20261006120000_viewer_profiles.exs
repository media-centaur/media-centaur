defmodule MediaCentaur.Repo.Migrations.ViewerProfiles do
  @moduledoc """
  Viewer profiles (ADR-078). The social context's `profiles` — what a
  key published about itself — becomes `social_profiles`, so the plain
  word is the viewer profile's. The new `profiles` holds one row per
  person who watches here, and the upgrade inserts the owner profile,
  "Me", so a single-profile install never sees the picker. Phase 2
  assigns every watching row to the oldest profile.
  """
  use Ecto.Migration

  def up do
    drop unique_index(:profiles, [:pubkey])
    rename table(:profiles), to: table(:social_profiles)
    create unique_index(:social_profiles, [:pubkey])

    create table(:profiles, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :hue, :integer
      add :picture_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    execute(fn ->
      repo().query!(
        """
        INSERT INTO profiles (id, name, inserted_at, updated_at)
        SELECT ?1, 'Me', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
        WHERE NOT EXISTS (SELECT 1 FROM profiles)
        """,
        [Ecto.UUID.generate()]
      )
    end)
  end

  def down do
    drop table(:profiles)
    drop unique_index(:social_profiles, [:pubkey])
    rename table(:social_profiles), to: table(:profiles)
    create unique_index(:profiles, [:pubkey])
  end
end
