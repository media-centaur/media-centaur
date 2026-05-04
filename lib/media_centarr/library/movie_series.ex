defmodule MediaCentarr.Library.MovieSeries do
  @moduledoc """
  A movie series (collection) in the library. Groups related movies together
  with shared metadata from TMDB.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_movie_series" do
    field :name, :string
    field :description, :string
    field :date_published, :string
    field :genres, {:array, :string}
    field :url, :string
    field :aggregate_rating_value, :float
    field :tmdb_id, :string

    has_many :movies, MediaCentarr.Library.Movie, foreign_key: :movie_series_id
    has_many :images, MediaCentarr.Library.Image, foreign_key: :movie_series_id
    has_many :extras, MediaCentarr.Library.Extra, foreign_key: :movie_series_id
    has_many :external_ids, MediaCentarr.Library.ExternalId, foreign_key: :movie_series_id
    has_many :watched_files, MediaCentarr.Library.WatchedFile, foreign_key: :movie_series_id

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :name,
      :description,
      :date_published,
      :genres,
      :url,
      :aggregate_rating_value,
      :tmdb_id
    ])
    |> validate_required([:name])
  end

  def update_changeset(movie_series, attrs) do
    cast(movie_series, attrs, [
      :name,
      :description,
      :date_published,
      :genres,
      :url,
      :aggregate_rating_value,
      :tmdb_id
    ])
  end
end
