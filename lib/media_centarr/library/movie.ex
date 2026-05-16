defmodule MediaCentarr.Library.Movie do
  @moduledoc """
  A child movie belonging to a `MovieSeries` entity. Parallel to `Episode`
  belonging to a `Season` — stores per-movie metadata from TMDB and the
  local `content_url` linking to the video file.

  `duration_seconds` is the canonical integer-seconds field (Library Schema
  v2 Phase 1 Task 3). The pipeline derives it from TMDB's `runtime`
  (minutes) at ingest time via `TMDB.Mapper.movie_attrs/3`. The prior
  stringly-typed `:duration` column was dropped; any previously-stored
  values are not recoverable but are repopulated on the next TMDB refresh.

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

  schema "library_movies" do
    field :name, :string
    field :description, :string
    field :date_published, :date
    field :duration_seconds, :integer
    field :director, :string
    field :content_rating, :string
    field :content_url, :string
    field :url, :string
    field :aggregate_rating_value, :float
    field :vote_count, :integer
    field :tagline, :string
    field :original_language, :string
    field :studio, :string
    field :country_code, :string
    field :position, :integer

    field :genres, {:array, :string}

    field :status, Ecto.Enum,
      values: [:released, :in_production, :post_production, :planned, :rumored, :canceled]

    embeds_many :cast, Person, on_replace: :delete
    embeds_many :crew, Person, on_replace: :delete

    belongs_to :movie_series, MediaCentarr.Library.MovieSeries
    has_many :images, MediaCentarr.Library.Image
    has_many :extras, MediaCentarr.Library.Extra
    has_many :external_ids, MediaCentarr.Library.ExternalId
    has_one :watch_progress, MediaCentarr.Library.WatchProgress

    # Polymorphic has_many via Ecto's `where:` filter. The `container_id` FK
    # is shared across container types; the discriminator keeps the
    # association scoped to this kind. See `Library.PlayableItem` moduledoc.
    has_many :playable_items, MediaCentarr.Library.PlayableItem,
      foreign_key: :container_id,
      where: [container_type: :movie]

    # WatchedFiles reach this Movie via its PlayableItems
    # (Library Schema v2 Phase 2 Task B). One Movie may host multiple
    # PlayableItems (director's cut etc.), each with its own
    # WatchedFile.
    has_many :watched_files, through: [:playable_items, :watched_files]

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :name,
      :description,
      :date_published,
      :duration_seconds,
      :director,
      :content_rating,
      :content_url,
      :url,
      :aggregate_rating_value,
      :vote_count,
      :tagline,
      :original_language,
      :studio,
      :country_code,
      :genres,
      :position,
      :movie_series_id,
      :status
    ])
    |> cast_embed(:cast, with: &Person.cast_member_changeset/2)
    |> cast_embed(:crew, with: &Person.crew_member_changeset/2)
    |> validate_required([:name])
  end

  def set_content_url_changeset(movie, attrs) do
    cast(movie, attrs, [:content_url])
  end

  @doc """
  Replaces the credits embeds in place — used by
  `MediaCentarr.Maintenance.refresh_movie_credits/0` to backfill cast
  and crew from a fresh TMDB fetch. `cast_embed` is required here
  because `Ecto.Changeset.change/2` cannot coerce maps into
  `embeds_many` entries.

  The IMDB id no longer lives on this schema; the credits-refresh
  call site writes it separately via `Library.ExternalIds.put(:imdb,
  movie, id)` after this changeset has been applied.
  """
  def update_credits_changeset(movie, attrs) do
    movie
    |> change()
    |> Person.put_credits(attrs)
  end
end
