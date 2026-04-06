defmodule MediaCentaur.Library.TVSeries do
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
    field :number_of_seasons, :integer
    field :status, Ecto.Enum, values: [:returning, :ended, :canceled, :in_production, :planned]

    has_many :seasons, MediaCentaur.Library.Season, foreign_key: :tv_series_id
    has_many :images, MediaCentaur.Library.Image, foreign_key: :tv_series_id
    has_many :extras, MediaCentaur.Library.Extra, foreign_key: :tv_series_id
    has_many :external_ids, MediaCentaur.Library.ExternalId, foreign_key: :tv_series_id
    has_many :watched_files, MediaCentaur.Library.WatchedFile, foreign_key: :tv_series_id

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
      :number_of_seasons,
      :status
    ])
    |> validate_required([:name])
  end

  def update_changeset(tv_series, attrs) do
    tv_series
    |> cast(attrs, [
      :name,
      :description,
      :date_published,
      :genres,
      :url,
      :aggregate_rating_value,
      :number_of_seasons,
      :status
    ])
  end
end
