defmodule MediaCentaur.ReleaseTracking.Item do
  @moduledoc """
  A movie or TV series being tracked for upcoming releases.

  The link back to the Library is a `(library_container_type,
  library_container_id)` discriminator pair, matching the polymorphic
  shape used by Image / Extra / ExternalId (Phase 2 D/E/F). The
  container is always a Library container — never a playable leaf —
  because a tracked release maps to a series or a movie collection,
  not a specific episode or movie file.

  `media_type` is the kind of content (`:movie` or `:tv_series`) and
  drives release shape and grab orchestration; `library_container_type`
  names the Library schema of the linked container, when there is one.
  Together they identify the TMDB resource: a `:movie` item linked to a
  `MovieSeries` tracks a TMDB *collection* (the Scanner writes these),
  while a `:movie` item with no link tracks one film (a manual track from
  search) — `Refresher` dispatches on exactly that.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @container_types [:movie, :tv_series, :movie_series, :video_object]

  @type t :: %__MODULE__{}

  schema "release_tracking_items" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    field :status, Ecto.Enum, values: [:watching, :ignored], default: :watching
    field :source, Ecto.Enum, values: [:library, :manual], default: :library
    field :library_container_type, Ecto.Enum, values: @container_types
    field :library_container_id, Ecto.UUID
    field :last_refreshed_at, :utc_datetime
    # TMDB origin_country ISO codes (TV only) — self-heals on refresh
    # for rows created before the column existed.
    field :origin_country, {:array, :string}
    # How TMDB spells this title elsewhere (`TMDB.Identifiers`), handed
    # to the drop planner's plans so an unattended grab can be verified
    # against the ids indexers declare. Self-heals on refresh.
    field :imdb_id, :string
    field :tvdb_id, :string
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

    has_many :releases, MediaCentaur.ReleaseTracking.Release
    has_many :events, MediaCentaur.ReleaseTracking.Event

    timestamps()
  end

  # "ask" (ADR-056 Q3): drop plans land as ready-awaiting-approval
  # drafts instead of auto-committing. "all_releases" is the full-auto
  # posture (legacy name preserved across the plan-convergence cutover).
  @auto_grab_modes ~w(global off ask all_releases)
  # `min_quality` additionally admits "any" — the per-title "best
  # available" acceptance (ADR-063 §2); it is not a ceiling value.
  @quality_values ~w(hd_1080p uhd_4k)

  @doc """
  Whether the title carries the per-title acceptance (ADR-063 §2): its
  searches take the best release that exists instead of holding to the
  quality preference. Set by "Take lower quality" on a plan board, reset
  from the title's automation settings.
  """
  @spec lower_quality_accepted?(%__MODULE__{}) :: boolean()
  def lower_quality_accepted?(%__MODULE__{min_quality: min_quality}), do: min_quality == "any"

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
      :origin_country,
      :imdb_id,
      :tvdb_id,
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
      :origin_country,
      :imdb_id,
      :tvdb_id,
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
    |> validate_inclusion(:min_quality, ["any" | @quality_values])
    |> validate_inclusion(:max_quality, @quality_values)
    |> validate_number(:quality_4k_patience_hours,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 24 * 30
    )
  end
end
