defmodule MediaCentarr.Library.Extra do
  @moduledoc """
  A bonus feature (featurette, behind-the-scenes, deleted scene) belonging to
  a movie, TV series, movie series, or season. Extras live in subdirectories
  like `Extras/` alongside the main media files and are serialized as
  `hasPart` -> `VideoObject` entries.

  File-on-disk presence is tracked separately via `Library.ExtraFile` —
  one ExtraFile per observed path. `content_url` here is the canonical
  playable path; ExtraFile rows record which watch directory the file
  was seen in.

  Follow-up: Wire `Library.Inbound` to write ExtraFile rows when
  ingesting bonus-feature paths. Today the only writer is the Phase 2
  Task B migration that backfills orphan WatchedFiles into ExtraFiles
  for collection-level Extras.
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

    belongs_to :season, MediaCentarr.Library.Season
    belongs_to :movie, MediaCentarr.Library.Movie
    belongs_to :tv_series, MediaCentarr.Library.TVSeries
    belongs_to :movie_series, MediaCentarr.Library.MovieSeries

    has_many :files, MediaCentarr.Library.ExtraFile

    timestamps()
  end

  def create_changeset(attrs) do
    cast(%__MODULE__{}, attrs, [
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
