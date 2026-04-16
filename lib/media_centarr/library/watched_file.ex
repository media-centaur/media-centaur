defmodule MediaCentarr.Library.WatchedFile do
  @moduledoc """
  Links a video file to its resolved library entity.

  A pure join between a file path and the entity the pipeline resolved it to.
  File presence tracking (present/absent state) lives in the Watcher context
  via `Watcher.KnownFile`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_watched_files" do
    field :file_path, :string
    field :watch_dir, :string

    belongs_to :movie, MediaCentarr.Library.Movie
    belongs_to :tv_series, MediaCentarr.Library.TVSeries
    belongs_to :movie_series, MediaCentarr.Library.MovieSeries
    belongs_to :video_object, MediaCentarr.Library.VideoObject

    timestamps()
  end

  def link_file_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :file_path,
      :watch_dir,
      :movie_id,
      :tv_series_id,
      :movie_series_id,
      :video_object_id
    ])
    |> validate_required([:file_path])
  end

  def link_file_changeset(watched_file, attrs) do
    watched_file
    |> cast(attrs, [
      :file_path,
      :watch_dir,
      :movie_id,
      :tv_series_id,
      :movie_series_id,
      :video_object_id
    ])
  end
end
