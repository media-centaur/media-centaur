defmodule MediaCentaur.Library.MediaTrackOverride do
  @moduledoc """
  Per-entity remembered audio + subtitle track selection. When the user
  manually changes tracks during mpv playback and the new selection
  differs from what the language policy chose, the selection is captured
  here so the next play of the same entity (next episode of a series,
  rewatch of a movie) honours it.

  The owner is identified by the discriminator pair `(owner_type,
  owner_id)`. `owner_type` is one of `:tv_series`, `:movie`,
  `:video_object` — every container that is watched as a unit and can
  therefore be re-watched with the same track choice. `:movie_series` is
  absent because a collection is never played directly; its child movies
  carry their own overrides. Unique within `(owner_type, owner_id)` —
  one override row per entity, updated in place via upsert.

  Overrides are **partial**: any of the four override fields may be
  unset, in which case that aspect falls back to the policy.

    * `audio_lang = nil`     → audio follows policy
    * `subtitle_lang = nil` and `subtitles_off = false` → subs follow policy
    * `subtitle_lang = nil` and `subtitles_off = true`  → subs explicitly disabled for this entity
    * `subtitle_forced` is meaningful only when `subtitle_lang` is set

  Stored as **language descriptors** (`"jpn"`, `"eng"`), not raw track
  indices — so an override survives re-rips and release-group changes
  that reorder track indices in the file.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @owner_types [:tv_series, :movie, :video_object]

  @type owner_type :: :tv_series | :movie | :video_object
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          owner_type: owner_type() | nil,
          owner_id: Ecto.UUID.t() | nil,
          audio_lang: String.t() | nil,
          subtitle_lang: String.t() | nil,
          subtitle_forced: boolean(),
          subtitles_off: boolean()
        }

  schema "library_media_track_overrides" do
    field :owner_type, Ecto.Enum, values: @owner_types
    field :owner_id, Ecto.UUID

    field :audio_lang, :string
    field :subtitle_lang, :string
    field :subtitle_forced, :boolean, default: false
    field :subtitles_off, :boolean, default: false

    timestamps()
  end

  def owner_types, do: @owner_types

  @doc """
  Changeset for insert or full update. Owner identity (`owner_type`,
  `owner_id`) is required; override fields are all optional and default
  to the "follow policy" interpretation.
  """
  def changeset(override, attrs) do
    override
    |> cast(attrs, [
      :owner_type,
      :owner_id,
      :audio_lang,
      :subtitle_lang,
      :subtitle_forced,
      :subtitles_off
    ])
    |> validate_required([:owner_type, :owner_id])
    |> validate_subtitle_consistency()
    |> unique_constraint([:owner_type, :owner_id],
      name: :library_media_track_overrides_owner_type_owner_id_index
    )
  end

  # `subtitles_off = true` means "explicitly disabled for this entity" —
  # which is mutually exclusive with picking a subtitle language. Reject
  # the contradiction at the changeset boundary rather than letting
  # downstream code disambiguate.
  defp validate_subtitle_consistency(changeset) do
    subtitles_off = get_field(changeset, :subtitles_off)
    subtitle_lang = get_field(changeset, :subtitle_lang)

    if subtitles_off && subtitle_lang do
      add_error(
        changeset,
        :subtitles_off,
        "cannot be true when subtitle_lang is set"
      )
    else
      changeset
    end
  end
end
