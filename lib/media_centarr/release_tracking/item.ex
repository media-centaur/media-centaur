defmodule MediaCentarr.ReleaseTracking.Item do
  @moduledoc """
  A movie or TV series being tracked for upcoming releases.

  The link back to the Library is a `(library_container_type,
  library_container_id)` discriminator pair, matching the polymorphic
  shape used by Image / Extra / ExternalId (Phase 2 D/E/F). The
  container is always a Library container — never a playable leaf —
  because a tracked release maps to a series or a movie collection,
  not a specific episode or movie file.

  `media_type` describes the TMDB resource (`:movie` or `:tv_series`)
  and drives TMDB API calls + grab orchestration; `library_container_type`
  describes the Library schema that owns the linked container. They
  happen to be 1:1 today (`:tv_series` → `:tv_series`, `:movie` →
  `:movie_series`) but the two questions are different — keep them
  separate so a future solo-movie link can coexist with collection
  tracking.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @container_types [:movie, :tv_series, :movie_series, :video_object]

  schema "release_tracking_items" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    field :status, Ecto.Enum, values: [:watching, :ignored], default: :watching
    field :source, Ecto.Enum, values: [:library, :manual], default: :library
    field :library_container_type, Ecto.Enum, values: @container_types
    field :library_container_id, Ecto.UUID
    field :last_refreshed_at, :utc_datetime
    field :poster_path, :string
    field :backdrop_path, :string
    field :logo_path, :string
    field :last_library_season, :integer, default: 0
    field :last_library_episode, :integer, default: 0
    field :dismiss_released_before, :date

    # Auto-grab per-item preferences.
    # `auto_grab_mode` `"global"` means inherit the global default from
    # `Settings`. Concrete overrides are `"off"` and `"all_releases"`.
    # Nullable quality fields inherit the global default when nil.
    field :auto_grab_mode, :string, default: "global"
    field :min_quality, :string
    field :max_quality, :string
    field :quality_4k_patience_hours, :integer
    field :prefer_season_packs, :boolean, default: false

    has_many :releases, MediaCentarr.ReleaseTracking.Release
    has_many :events, MediaCentarr.ReleaseTracking.Event

    timestamps()
  end

  @auto_grab_modes ~w(global off all_releases)
  @quality_values ~w(hd_1080p uhd_4k)

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :tmdb_id,
      :media_type,
      :name,
      :status,
      :source,
      :library_container_type,
      :library_container_id,
      :last_refreshed_at,
      :poster_path,
      :backdrop_path,
      :logo_path,
      :last_library_season,
      :last_library_episode
    ])
    |> validate_required([:tmdb_id, :media_type, :name])
    |> validate_container_pair()
    |> unique_constraint([:tmdb_id, :media_type],
      name: "release_tracking_items_tmdb_id_media_type_index"
    )
  end

  def update_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name,
      :status,
      :library_container_type,
      :library_container_id,
      :last_refreshed_at,
      :poster_path,
      :backdrop_path,
      :logo_path,
      :last_library_season,
      :last_library_episode,
      :dismiss_released_before
    ])
    |> validate_container_pair()
  end

  # Both halves of the discriminator pair must be filled in together
  # or neither must be filled. Half-set rows ("type without id" /
  # "id without type") have no meaning and produce confusing query
  # behaviour downstream.
  defp validate_container_pair(changeset) do
    container_type = get_field(changeset, :library_container_type)
    container_id = get_field(changeset, :library_container_id)

    case {container_type, container_id} do
      {nil, nil} ->
        changeset

      {type, id} when not is_nil(type) and not is_nil(id) ->
        changeset

      {nil, _id} ->
        add_error(
          changeset,
          :library_container_type,
          "must be set when library_container_id is set"
        )

      {_type, nil} ->
        add_error(
          changeset,
          :library_container_id,
          "must be set when library_container_type is set"
        )
    end
  end

  @doc """
  Changeset for the per-item auto-grab preferences. Validates enum-like
  string fields and rejects unknown modes/qualities at the boundary so
  the policy never has to handle malformed input.
  """
  def auto_grab_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :auto_grab_mode,
      :min_quality,
      :max_quality,
      :quality_4k_patience_hours,
      :prefer_season_packs
    ])
    |> validate_inclusion(:auto_grab_mode, @auto_grab_modes)
    |> validate_inclusion(:min_quality, @quality_values)
    |> validate_inclusion(:max_quality, @quality_values)
    |> validate_number(:quality_4k_patience_hours,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 24 * 30
    )
  end
end
