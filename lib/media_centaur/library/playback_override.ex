defmodule MediaCentaur.Library.PlaybackOverride do
  @moduledoc """
  One profile's remembered playback settings for one entity (ADR-078):
  where the viewer, during playback, moved away from the default — the
  audio and subtitle tracks the language policy chose, and the picture's
  Fit. The settings are captured here so the next play of the same
  entity (next episode of a series, rewatch of a movie) by the same
  profile honours them. The profile is a plain id, not an association —
  `Profiles` is another context.

  The owner is identified by the discriminator pair `(owner_type,
  owner_id)`. `owner_type` is one of `:tv_series`, `:movie`,
  `:video_object` — every container that is watched as a unit and can
  therefore be re-watched with the same track choice. `:movie_series` is
  absent because a collection is never played directly; its child movies
  carry their own overrides. Unique within `(profile_id, owner_type,
  owner_id)` — one override row per profile and entity, updated in place
  via upsert.

  Three settings, each overridden on its own and **unset** when it follows
  its default — overriding one never overrides another:

    * `audio_lang = nil`     → audio follows policy
    * `subtitle_lang = nil` and `subtitles_off = false` → subs follow policy
    * `subtitle_lang = nil` and `subtitles_off = true`  → subs explicitly disabled for this entity
    * `subtitle_forced` is meaningful only when `subtitle_lang` is set
    * `fill_width = nil`     → the picture follows its default, Fit;
      `false` → Fit, chosen; `true` → it fills the screen's width, for a
      title whose frame carries black bars (a remote player's
      `user-data/fill-width`)

  `follows_default?/2` reads one setting; `default_attrs/1` is what puts
  one setting back on its default and leaves the others alone.

  Stored as **language descriptors** (`"jpn"`, `"eng"`), not raw track
  indices — so an override survives re-rips and release-group changes
  that reorder track indices in the file.
  """
  use Ecto.Schema
  @behaviour MediaCentaur.Library.OwnerTyped
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @owner_types [:tv_series, :movie, :video_object]

  @type owner_type :: :tv_series | :movie | :video_object
  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          profile_id: Ecto.UUID.t() | nil,
          owner_type: owner_type() | nil,
          owner_id: Ecto.UUID.t() | nil,
          audio_lang: String.t() | nil,
          subtitle_lang: String.t() | nil,
          subtitle_forced: boolean(),
          subtitles_off: boolean(),
          fill_width: boolean() | nil
        }

  @typedoc "One of the overridable settings."
  @type setting :: :audio | :subtitles | :picture

  schema "library_playback_overrides" do
    field :profile_id, Ecto.UUID
    field :owner_type, Ecto.Enum, values: @owner_types
    field :owner_id, Ecto.UUID

    field :audio_lang, :string
    field :subtitle_lang, :string
    field :subtitle_forced, :boolean, default: false
    field :subtitles_off, :boolean, default: false
    field :fill_width, :boolean

    timestamps()
  end

  def owner_types, do: @owner_types

  @doc "Whether `setting` follows its default — no override, or none for that setting."
  @spec follows_default?(t() | nil, setting()) :: boolean()
  def follows_default?(nil, _setting), do: true
  def follows_default?(%__MODULE__{audio_lang: lang}, :audio), do: is_nil(lang)

  def follows_default?(%__MODULE__{subtitle_lang: lang, subtitles_off: off}, :subtitles),
    do: is_nil(lang) and not off

  def follows_default?(%__MODULE__{fill_width: fill}, :picture), do: is_nil(fill)

  @doc "The fields that put `setting` back on its default, leaving the other settings as they are."
  @spec default_attrs(setting()) :: map()
  def default_attrs(:audio), do: %{audio_lang: nil}
  def default_attrs(:subtitles), do: %{subtitle_lang: nil, subtitle_forced: false, subtitles_off: false}
  def default_attrs(:picture), do: %{fill_width: nil}

  @doc """
  Changeset for insert or full update. The profile and the owner identity
  (`profile_id`, `owner_type`, `owner_id`) are required; override fields
  are all optional and default to the "follow policy" interpretation.
  """
  def changeset(override, attrs) do
    override
    |> cast(attrs, [
      :profile_id,
      :owner_type,
      :owner_id,
      :audio_lang,
      :subtitle_lang,
      :subtitle_forced,
      :subtitles_off,
      :fill_width
    ])
    |> validate_required([:profile_id, :owner_type, :owner_id])
    |> validate_subtitle_consistency()
    |> unique_constraint([:profile_id, :owner_type, :owner_id],
      name: :library_playback_overrides_profile_id_owner_type_owner_id_index
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
