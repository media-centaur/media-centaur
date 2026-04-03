defmodule MediaCentaur.Library.Identifier do
  @moduledoc """
  An external identifier linking an entity to a third-party service
  (TMDB, IMDB, etc.). Modelled as a schema.org `PropertyValue`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_identifiers" do
    field :property_id, :string
    field :value, :string

    belongs_to :movie, MediaCentaur.Library.Movie
    belongs_to :tv_series, MediaCentaur.Library.TVSeries
    belongs_to :movie_series, MediaCentaur.Library.MovieSeries
    belongs_to :video_object, MediaCentaur.Library.VideoObject

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :property_id,
      :value,
      :movie_id,
      :tv_series_id,
      :movie_series_id,
      :video_object_id
    ])
    |> validate_required([:property_id, :value])
  end
end
