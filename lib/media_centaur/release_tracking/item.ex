defmodule MediaCentaur.ReleaseTracking.Item do
  @moduledoc """
  A movie or TV series being tracked for upcoming releases.

  The link back to the Library is a `(library_container_type,
  library_container_id)` discriminator pair, matching the polymorphic
  shape used by Image / Extra / ExternalId (Phase 2 D/E/F). The
  container is always a Library container — never a playable leaf —
  because a tracked release maps to a series or a movie collection,
  not a specific episode or movie file.

  `tracking_mode` is the one automation field ([ADR-065]) — it replaced
  `status` and `auto_grab_mode`, which were two representations of one
  idea. It is set only by a person, or seeded once at creation, and is
  **never raised by the system**. There is no `source`: why a title is
  tracked is a *reason*, queried from its owner (`Reasons`), not
  write-once metadata that goes stale the moment a title has both causes.

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

  @typedoc """
  What the app does about a tracked title.

    * `:none` — inert: no calendar refresh, no wants, invisible. The
      durable record of a deliberate disarm, which survives with no
      tracking reason held so that re-acquiring or re-listing the title
      cannot silently re-arm it.
    * `:watch` — keep the calendar, grab nothing.
    * `:ask` — park a draft plan when a release drops.
    * `:grab` — grab it.
    * `:global` — follow the global auto-grab default, live. Only while
      the mode has never been set explicitly: an explicit mode is a
      concrete value and so is immune to a change of the global setting.
  """
  @type tracking_mode :: :none | :watch | :ask | :grab | :global

  @type t :: %__MODULE__{}

  schema "release_tracking_items" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    field :tracking_mode, Ecto.Enum, values: [:none, :watch, :ask, :grab, :global], default: :global
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
    # The title in its original language, when TMDB's canonical title is
    # a localised one. Self-heals on refresh.
    field :original_title, :string
    field :last_library_season, :integer, default: 0
    field :last_library_episode, :integer, default: 0
    field :dismiss_released_before, :date

    # Per-item quality preferences. Nullable fields inherit the global
    # default when nil; the mode itself is `tracking_mode` above.
    field :min_quality, :string
    field :max_quality, :string
    field :quality_4k_patience_hours, :integer
    field :prefer_season_packs, :boolean, default: false

    has_many :releases, MediaCentaur.ReleaseTracking.Release
    has_many :events, MediaCentaur.ReleaseTracking.Event

    timestamps()
  end

  # `min_quality` additionally admits "any" — the per-title "best
  # available" acceptance (ADR-063 §2); it is not a ceiling value.
  @quality_values ~w(hd_1080p uhd_4k)

  @doc """
  Resolves a `tracking_mode` into the grab decision the acquisition side
  acts on: `"off"`, `"ask"` or `"all_releases"`.

  The single representation of that mapping. Acquisition asks whether it
  may grab; it does not model tracking, so the two modes that keep a
  calendar without grabbing — `:none` (inert) and `:watch` — are both
  simply off from there. `:global` defers to the global default, live,
  which is what makes flipping the global switch stop every title whose
  mode has never been set explicitly.
  """
  @spec grab_mode(tracking_mode() | nil, String.t()) :: String.t()
  def grab_mode(mode, default) when mode in [nil, :global], do: default
  def grab_mode(:grab, _default), do: "all_releases"
  def grab_mode(:ask, _default), do: "ask"
  def grab_mode(mode, _default) when mode in [:none, :watch], do: "off"

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
      :tracking_mode,
      :library_container_type,
      :library_container_id,
      :last_refreshed_at,
      :origin_country,
      :imdb_id,
      :tvdb_id,
      :original_title,
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
      :tracking_mode,
      :library_container_type,
      :library_container_id,
      :last_refreshed_at,
      :origin_country,
      :imdb_id,
      :tvdb_id,
      :original_title,
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
  Changeset for the per-item automation preferences: the tracking mode
  and the quality bounds. Rejects unknown modes/qualities at the boundary
  so the policy never has to handle malformed input.
  """
  def automation_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :tracking_mode,
      :min_quality,
      :max_quality,
      :quality_4k_patience_hours,
      :prefer_season_packs
    ])
    |> validate_required([:tracking_mode])
    |> validate_inclusion(:min_quality, ["any" | @quality_values])
    |> validate_inclusion(:max_quality, @quality_values)
    |> validate_number(:quality_4k_patience_hours,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 24 * 30
    )
  end
end
