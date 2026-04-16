defmodule MediaCentarr.Library.VideoObject do
  @moduledoc """
  A standalone video object in the library. Represents a single video file
  that doesn't belong to a TV series or movie series — e.g. a concert,
  documentary, or home video.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_video_objects" do
    field :name, :string
    field :description, :string
    field :date_published, :string
    field :content_url, :string
    field :url, :string

    has_many :images, MediaCentarr.Library.Image, foreign_key: :video_object_id
    has_many :external_ids, MediaCentarr.Library.ExternalId, foreign_key: :video_object_id
    has_many :watched_files, MediaCentarr.Library.WatchedFile, foreign_key: :video_object_id
    has_one :watch_progress, MediaCentarr.Library.WatchProgress, foreign_key: :video_object_id

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :id,
      :name,
      :description,
      :date_published,
      :content_url,
      :url
    ])
    |> validate_required([:name])
  end

  def update_changeset(video_object, attrs) do
    video_object
    |> cast(attrs, [
      :name,
      :description,
      :date_published,
      :content_url,
      :url
    ])
  end
end
