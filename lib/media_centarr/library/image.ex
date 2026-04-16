defmodule MediaCentarr.Library.Image do
  @moduledoc """
  An image associated with a media entity — poster, backdrop, logo, or thumb.

  Each entity has at most one image per role, enforced by the `unique_entity_role`
  identity and the `find_or_create` upsert action.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_images" do
    field :role, :string
    field :content_url, :string
    field :extension, :string

    belongs_to :movie, MediaCentarr.Library.Movie
    belongs_to :episode, MediaCentarr.Library.Episode
    belongs_to :tv_series, MediaCentarr.Library.TVSeries
    belongs_to :movie_series, MediaCentarr.Library.MovieSeries
    belongs_to :video_object, MediaCentarr.Library.VideoObject

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :role,
      :content_url,
      :extension,
      :movie_id,
      :episode_id,
      :tv_series_id,
      :movie_series_id,
      :video_object_id
    ])
    |> validate_required([:role])
  end

  def update_changeset(image, attrs) do
    image
    |> cast(attrs, [:content_url, :extension])
  end
end
