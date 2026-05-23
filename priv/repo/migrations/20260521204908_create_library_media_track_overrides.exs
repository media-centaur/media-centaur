defmodule MediaCentaur.Repo.Migrations.CreateLibraryMediaTrackOverrides do
  @moduledoc """
  Per-entity audio + subtitle track overrides used by the playback
  language policy. When the user manually changes tracks inside mpv, the
  selection is captured as a language descriptor (not a raw track index)
  so it survives re-rips and release-group changes.

  Polymorphic via `(owner_type, owner_id)` — `owner_type` ∈ {`:tv_series`,
  `:movie`} for v1. Schema follows the convention established by
  `library_images`, `library_extras`, and `library_external_ids`
  (see `20260516104406_polymorphic_owner_discriminators.exs`). Adding
  `:season` or `:movie_series` later is a one-line enum extension.

  Unique on `(owner_type, owner_id)` — one override row per entity. The
  override is updated in place via upsert when capture fires.
  """
  use Ecto.Migration

  def up do
    create table(:library_media_track_overrides, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false

      add :audio_lang, :string
      add :subtitle_lang, :string
      add :subtitle_forced, :boolean, null: false, default: false
      add :subtitles_off, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:library_media_track_overrides, [:owner_type, :owner_id],
             name: :library_media_track_overrides_owner_type_owner_id_index
           )
  end

  def down do
    drop table(:library_media_track_overrides)
  end
end
