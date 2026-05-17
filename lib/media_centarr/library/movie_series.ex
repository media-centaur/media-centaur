defmodule MediaCentarr.Library.MovieSeries do
  @moduledoc """
  A movie series (collection) in the library. Groups related movies together
  with shared metadata from TMDB.

  Carries the same metadata surface as `TVSeries` (tagline, language, studio,
  country, status, cast, crew, vote_count) so detail pages render both
  containers with the same shape. TMDB collection endpoints expose fewer of
  these fields directly — most ingest-time values come back `nil` and are
  filled in by maintenance/refresh paths. See Phase 1 Task 4 of the Library
  Schema v2 campaign (`campaigns/done/library-schema-v2.md`).

  TMDB ids (source `"tmdb_collection"`) live in `Library.ExternalId` rows
  reachable via the `:external_ids` association — no longer a column on
  this schema (Library Schema v2 Phase 1 Task 6).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MediaCentarr.Library.Person

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_movie_series" do
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

    # TMDB collections do not carry an explicit status; this mirrors the
    # TVSeries status enum so the detail surface can render the same field
    # uniformly. Values are derived from constituent movies when available
    # (today: left nil at ingest, populated by future enrichment).
    field :status, Ecto.Enum, values: [:released, :ongoing, :ended]

    embeds_many :cast, Person, on_replace: :delete
    embeds_many :crew, Person, on_replace: :delete

    has_many :movies, MediaCentarr.Library.Movie, foreign_key: :movie_series_id

    # Polymorphic associations — Image / Extra / ExternalId rows discriminate
    # on `(owner_type, owner_id)` (Library Schema v2 Phase 2 Tasks D, E, F).
    has_many :images, MediaCentarr.Library.Image,
      foreign_key: :owner_id,
      where: [owner_type: :movie_series]

    has_many :extras, MediaCentarr.Library.Extra,
      foreign_key: :owner_id,
      where: [owner_type: :movie_series]

    has_many :external_ids, MediaCentarr.Library.ExternalId,
      foreign_key: :owner_id,
      where: [owner_type: :movie_series]

    # WatchedFiles reach this MovieSeries via its child movies' PlayableItems
    # (Library Schema v2 Phase 2 Task B). The MovieSeries itself never owns
    # a WatchedFile directly.
    has_many :watched_files, through: [:movies, :watched_files]

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
    :status
  ]

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> cast_embed(:cast, with: &Person.cast_member_changeset/2)
    |> cast_embed(:crew, with: &Person.crew_member_changeset/2)
    |> validate_required([:name])
  end

  def update_changeset(movie_series, attrs) do
    movie_series
    |> cast(attrs, @fields -- [:id])
    |> cast_embed(:cast, with: &Person.cast_member_changeset/2)
    |> cast_embed(:crew, with: &Person.crew_member_changeset/2)
  end

  @doc """
  Replaces the credits embeds in place — used by
  `MediaCentarr.Maintenance.refresh_movie_series_credits/0` to backfill
  cast and crew from a fresh TMDB fetch. `cast_embed` is required here
  because `Ecto.Changeset.change/2` cannot coerce maps into
  `embeds_many` entries.
  """
  def update_credits_changeset(movie_series, attrs) do
    movie_series
    |> change()
    |> Person.put_credits(attrs)
  end
end
