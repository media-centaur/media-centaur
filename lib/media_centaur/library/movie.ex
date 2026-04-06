defmodule MediaCentaur.Library.Movie do
  @moduledoc """
  A child movie belonging to a `MovieSeries` entity. Parallel to `Episode`
  belonging to a `Season` — stores per-movie metadata from TMDB and the
  local `content_url` linking to the video file.
  """
  use Ecto.Schema
  import Ecto.Changeset

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
    field :tmdb_id, :string
    field :position, :integer

    field :genres, {:array, :string}

    field :status, Ecto.Enum,
      values: [:released, :in_production, :post_production, :planned, :rumored, :canceled]

    belongs_to :movie_series, MediaCentaur.Library.MovieSeries
    has_many :images, MediaCentaur.Library.Image
    has_many :extras, MediaCentaur.Library.Extra
    has_many :external_ids, MediaCentaur.Library.ExternalId
    has_many :watched_files, MediaCentaur.Library.WatchedFile
    has_one :watch_progress, MediaCentaur.Library.WatchProgress

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
      :tmdb_id,
      :genres,
      :position,
      :movie_series_id,
      :status
    ])
    |> validate_required([:name])
  end

  def set_content_url_changeset(movie, attrs) do
    movie
    |> cast(attrs, [:content_url])
  end
end
