defmodule MediaCentaur.Repo.Migrations.MediaTrackOverridesPerProfile do
  @moduledoc """
  Track memory — the audio and subtitle choice remembered per title —
  belongs to a profile (ADR-078, phase 2). Rebuild with `profile_id`,
  every existing row the oldest profile's, unique on
  `(profile_id, owner_type, owner_id)`. `(owner_type, owner_id)` keeps an
  index of its own for `EntityCascade`'s delete by owner, as the other
  polymorphic children carry (`20260516104406_polymorphic_owner_discriminators`);
  until now the old unique index served it. Not reversible.
  """
  use Ecto.Migration

  def up do
    create table(:library_media_track_overrides_next, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :profile_id, references(:profiles, type: :uuid, on_delete: :delete_all), null: false
      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false
      add :audio_lang, :string
      add :subtitle_lang, :string
      add :subtitle_forced, :boolean, null: false, default: false
      add :subtitles_off, :boolean, null: false, default: false

      timestamps()
    end

    execute """
    INSERT INTO library_media_track_overrides_next
      (id, profile_id, owner_type, owner_id, audio_lang, subtitle_lang, subtitle_forced, subtitles_off,
       inserted_at, updated_at)
    SELECT id, (SELECT id FROM profiles ORDER BY inserted_at, id LIMIT 1), owner_type, owner_id,
           audio_lang, subtitle_lang, subtitle_forced, subtitles_off, inserted_at, updated_at
    FROM library_media_track_overrides
    """

    drop table(:library_media_track_overrides)
    rename table(:library_media_track_overrides_next), to: table(:library_media_track_overrides)

    create unique_index(:library_media_track_overrides, [:profile_id, :owner_type, :owner_id],
             name: :library_media_track_overrides_profile_id_owner_type_owner_id_index
           )

    create index(:library_media_track_overrides, [:owner_type, :owner_id],
             name: :library_media_track_overrides_owner_index
           )
  end

  def down do
    raise Ecto.MigrationError,
          "media_track_overrides_per_profile is not reversible — rows of several profiles would collapse onto one owner"
  end
end
