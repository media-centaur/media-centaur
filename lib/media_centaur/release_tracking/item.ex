defmodule MediaCentaur.ReleaseTracking.Item do
  @moduledoc """
  A movie or TV series being tracked for upcoming releases.

  The link back to the Library is a `(library_container_type,
  library_container_id)` discriminator pair, matching the polymorphic
  shape used by Image / Extra / ExternalId (Phase 2 D/E/F). The
  container is always a Library container — never a playable leaf —
  because a tracked release maps to a series or a movie collection,
  not a specific episode or movie file.

  It carries no authored field at all. What a person wants done about the
  title is the rung on their `Discovery.TitleIntent`, and this row exists
  exactly while that rung is `:follow` or above — so there is nothing
  here to set, and nothing to keep in agreement with anything else. It
  carries no TMDB fact either: everything TMDB says about the title lives
  in `MediaCentaur.TMDB.Store`, and `name` and `season_sizes` are
  attached from it when items are loaded (ADR-071).

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
    field :library_container_type, Ecto.Enum, values: @container_types
    field :library_container_id, Ecto.UUID
    field :last_library_season, :integer, default: 0
    field :last_library_episode, :integer, default: 0
    field :dismiss_released_before, :date

    # Read from the TMDB store on load (`ReleaseTracking.Titles.attach/1`),
    # never stored: the title's name, and how many episodes each season of
    # a tracked show has, keyed by season-number string (`%{"1" => 22}`,
    # specials excluded) — the same shape as
    # `Acquisition.Plans.Plan.span_sizes`, the drop planner's fit
    # denominator. Everything else TMDB says about the title is read
    # from the store by whoever needs it (ADR-071).
    field :name, :string, virtual: true
    field :season_sizes, :map, virtual: true, default: %{}

    has_many :releases, MediaCentaur.ReleaseTracking.Release

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :tmdb_id,
      :media_type,
      :library_container_type,
      :library_container_id,
      :last_library_season,
      :last_library_episode
    ])
    |> validate_required([:tmdb_id, :media_type])
    |> validate_container_pair()
    |> unique_constraint([:tmdb_id, :media_type],
      name: "release_tracking_items_tmdb_id_media_type_index"
    )
  end

  def update_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :library_container_type,
      :library_container_id,
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
end
