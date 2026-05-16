defmodule MediaCentarr.Library.TVSeries do
  @moduledoc """
  A TV series in the library. Top-level container for seasons and episodes,
  with metadata from TMDB.

  TMDB and IMDB ids live in `Library.ExternalId` rows reachable via the
  `:external_ids` association — they are no longer columns on this
  schema (Library Schema v2 Phase 1 Task 6). Read through
  `MediaCentarr.Library.ExternalIds.get/2`; write through
  `MediaCentarr.Library.ExternalIds.put/3`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MediaCentarr.Library.Person

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_tv_series" do
    field :name, :string
    field :description, :string
    field :date_published, :date
    field :genres, {:array, :string}
    field :url, :string
    field :aggregate_rating_value, :float
    field :vote_count, :integer
    field :tagline, :string
    field :original_language, :string
    field :studio, :string
    field :country_code, :string
    field :network, :string
    field :number_of_seasons, :integer
    field :status, Ecto.Enum, values: [:returning, :ended, :canceled, :in_production, :planned]

    embeds_many :cast, Person, on_replace: :delete
    embeds_many :crew, Person, on_replace: :delete

    has_many :seasons, MediaCentarr.Library.Season, foreign_key: :tv_series_id

    # Polymorphic associations — Image / Extra / ExternalId rows discriminate
    # on `(owner_type, owner_id)` (Library Schema v2 Phase 2 Tasks D, E, F).
    has_many :images, MediaCentarr.Library.Image,
      foreign_key: :owner_id,
      where: [owner_type: :tv_series]

    has_many :extras, MediaCentarr.Library.Extra,
      foreign_key: :owner_id,
      where: [owner_type: :tv_series]

    has_many :external_ids, MediaCentarr.Library.ExternalId,
      foreign_key: :owner_id,
      where: [owner_type: :tv_series]

    # WatchedFiles reach this TVSeries via its seasons' episodes'
    # PlayableItems (Library Schema v2 Phase 2 Task B). The TVSeries
    # itself never owns a WatchedFile directly.
    has_many :episodes, through: [:seasons, :episodes]

    has_many :watched_files,
      through: [:episodes, :watched_files]

    timestamps()
  end

  @fields [
    :id,
    :name,
    :description,
    :date_published,
    :genres,
    :url,
    :aggregate_rating_value,
    :vote_count,
    :tagline,
    :original_language,
    :studio,
    :country_code,
    :network,
    :number_of_seasons,
    :status
  ]

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> cast_embed(:cast, with: &Person.cast_member_changeset/2)
    |> cast_embed(:crew, with: &Person.crew_member_changeset/2)
    |> validate_required([:name])
  end

  def update_changeset(tv_series, attrs) do
    tv_series
    |> cast(attrs, @fields -- [:id])
    |> cast_embed(:cast, with: &Person.cast_member_changeset/2)
    |> cast_embed(:crew, with: &Person.crew_member_changeset/2)
  end

  @doc """
  Replaces the credits embeds in place — used by
  `MediaCentarr.Maintenance.refresh_series_credits/0` to backfill
  cast and crew (creators) from a fresh TMDB fetch. `cast_embed` is
  required here because `Ecto.Changeset.change/2` cannot coerce maps
  into `embeds_many` entries.

  The IMDB id no longer lives on this schema; the credits-refresh
  call site writes it separately via `Library.ExternalIds.put(:imdb,
  tv_series, id)` after this changeset has been applied.
  """
  def update_credits_changeset(tv_series, attrs) do
    tv_series
    |> change()
    |> Person.put_credits(attrs)
  end
end
