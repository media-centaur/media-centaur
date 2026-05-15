defmodule MediaCentarr.Library.Movie do
  @moduledoc """
  A child movie belonging to a `MovieSeries` entity. Parallel to `Episode`
  belonging to a `Season` — stores per-movie metadata from TMDB and the
  local `content_url` linking to the video file.
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
    field :date_published, :string
    field :duration, :string
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
    field :tmdb_id, :string
    field :imdb_id, :string
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
    has_many :watched_files, MediaCentarr.Library.WatchedFile
    has_one :watch_progress, MediaCentarr.Library.WatchProgress

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :name,
      :description,
      :date_published,
      :duration,
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
      :tmdb_id,
      :imdb_id,
      :genres,
      :position,
      :movie_series_id,
      :status
    ])
    |> cast_embed(:cast, with: &Person.cast_member_changeset/2)
    |> cast_embed(:crew, with: &Person.crew_member_changeset/2)
    |> validate_required([:name])
    |> unique_constraint(:tmdb_id, name: :library_movies_tmdb_id_index)
  end

  def set_content_url_changeset(movie, attrs) do
    cast(movie, attrs, [:content_url])
  end

  @doc """
  Replaces the credits embeds in place — used by
  `MediaCentarr.Maintenance.refresh_movie_credits/0` to backfill cast,
  crew, and `imdb_id` from a fresh TMDB fetch. `cast_embed` is required
  here because `Ecto.Changeset.change/2` cannot coerce maps into
  `embeds_many` entries.
  """
  def update_credits_changeset(movie, attrs) do
    movie
    |> change()
    |> Person.put_credits(attrs)
  end
end
