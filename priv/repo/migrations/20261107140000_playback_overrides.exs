defmodule MediaCentaur.Repo.Migrations.PlaybackOverrides do
  @moduledoc """
  Track memory becomes playback memory: the remembered audio and subtitle
  choice per title is joined by the picture's Fill width, so the table is
  renamed for what it now holds and gains `fill_width` (false = Fit, the
  default). The indexes are renamed with it.
  """
  use Ecto.Migration

  def up do
    drop index(:library_media_track_overrides, [:profile_id, :owner_type, :owner_id],
           name: :library_media_track_overrides_profile_id_owner_type_owner_id_index
         )

    drop index(:library_media_track_overrides, [:owner_type, :owner_id],
           name: :library_media_track_overrides_owner_index
         )

    rename table(:library_media_track_overrides), to: table(:library_playback_overrides)

    alter table(:library_playback_overrides) do
      add :fill_width, :boolean, null: false, default: false
    end

    create unique_index(:library_playback_overrides, [:profile_id, :owner_type, :owner_id],
             name: :library_playback_overrides_profile_id_owner_type_owner_id_index
           )

    create index(:library_playback_overrides, [:owner_type, :owner_id],
             name: :library_playback_overrides_owner_index
           )
  end

  def down do
    drop index(:library_playback_overrides, [:profile_id, :owner_type, :owner_id],
           name: :library_playback_overrides_profile_id_owner_type_owner_id_index
         )

    drop index(:library_playback_overrides, [:owner_type, :owner_id],
           name: :library_playback_overrides_owner_index
         )

    alter table(:library_playback_overrides) do
      remove :fill_width
    end

    rename table(:library_playback_overrides), to: table(:library_media_track_overrides)

    create unique_index(:library_media_track_overrides, [:profile_id, :owner_type, :owner_id],
             name: :library_media_track_overrides_profile_id_owner_type_owner_id_index
           )

    create index(:library_media_track_overrides, [:owner_type, :owner_id],
             name: :library_media_track_overrides_owner_index
           )
  end
end
