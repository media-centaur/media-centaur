defmodule MediaCentaur.Library.Entity do
  @moduledoc """
  A media entity in the library — a movie, TV series, or generic video object.

  Entities are created from TMDB metadata and served to the user-interface
  via Phoenix Channels.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_entities" do
    field :type, Ecto.Enum, values: [:movie, :movie_series, :tv_series, :video_object]
    field :name, :string
    field :description, :string
    field :date_published, :string
    field :genres, {:array, :string}
    field :content_url, :string
    field :url, :string
    field :duration, :string
    field :director, :string
    field :content_rating, :string
    field :number_of_seasons, :integer
    field :aggregate_rating_value, :float

    has_many :images, MediaCentaur.Library.Image
    has_many :identifiers, MediaCentaur.Library.Identifier
    has_many :movies, MediaCentaur.Library.Movie
    has_many :extras, MediaCentaur.Library.Extra
    has_many :seasons, MediaCentaur.Library.Season
    has_many :watched_files, MediaCentaur.Library.WatchedFile
    has_many :watch_progress, MediaCentaur.Library.WatchProgress
    has_many :extra_progress, MediaCentaur.Library.ExtraProgress

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :type,
      :name,
      :description,
      :date_published,
      :genres,
      :url,
      :duration,
      :director,
      :content_rating,
      :content_url,
      :number_of_seasons,
      :aggregate_rating_value
    ])
    |> validate_required([:type, :name])
  end

  def set_content_url_changeset(entity, attrs) do
    entity
    |> cast(attrs, [:content_url])
  end
end
