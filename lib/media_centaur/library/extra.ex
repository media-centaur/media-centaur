defmodule MediaCentaur.Library.Extra do
  @moduledoc """
  A bonus feature (featurette, behind-the-scenes, deleted scene) belonging to
  a movie, TV series, movie series, or season. Extras live in subdirectories
  like `Extras/` alongside the main media files and are serialized as
  `hasPart` -> `VideoObject` entries.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_extras" do
    field :name, :string
    field :content_url, :string
    field :position, :integer

    belongs_to :season, MediaCentaur.Library.Season
    belongs_to :movie, MediaCentaur.Library.Movie
    belongs_to :tv_series, MediaCentaur.Library.TVSeries
    belongs_to :movie_series, MediaCentaur.Library.MovieSeries

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :name,
      :content_url,
      :position,
      :season_id,
      :movie_id,
      :tv_series_id,
      :movie_series_id
    ])
  end
end
