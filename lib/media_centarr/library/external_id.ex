defmodule MediaCentarr.Library.ExternalId do
  @moduledoc """
  An external identifier linking an entity to a third-party service
  (TMDB, IMDB, etc.). Stored as `{source, external_id}` per row.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_external_ids" do
    field :source, :string
    field :external_id, :string

    belongs_to :movie, MediaCentarr.Library.Movie
    belongs_to :tv_series, MediaCentarr.Library.TVSeries
    belongs_to :movie_series, MediaCentarr.Library.MovieSeries
    belongs_to :video_object, MediaCentarr.Library.VideoObject

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :source,
      :external_id,
      :movie_id,
      :tv_series_id,
      :movie_series_id,
      :video_object_id
    ])
    |> validate_required([:source, :external_id])
  end
end
