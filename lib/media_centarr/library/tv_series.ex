defmodule MediaCentarr.Library.TVSeries do
  @moduledoc """
  A TV series in the library. Top-level container for seasons and episodes,
  with metadata from TMDB.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_tv_series" do
    field :name, :string
    field :description, :string
    field :date_published, :string
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

    has_many :seasons, MediaCentarr.Library.Season, foreign_key: :tv_series_id
    has_many :images, MediaCentarr.Library.Image, foreign_key: :tv_series_id
    has_many :extras, MediaCentarr.Library.Extra, foreign_key: :tv_series_id
    has_many :external_ids, MediaCentarr.Library.ExternalId, foreign_key: :tv_series_id
    has_many :watched_files, MediaCentarr.Library.WatchedFile, foreign_key: :tv_series_id

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
      :vote_count,
      :tagline,
      :original_language,
      :studio,
      :country_code,
      :network,
      :number_of_seasons,
      :status
    ])
    |> validate_required([:name])
  end

  def update_changeset(tv_series, attrs) do
    cast(tv_series, attrs, [
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
    ])
  end
end
