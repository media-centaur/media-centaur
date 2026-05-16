defmodule MediaCentarr.Library.Extra do
  @moduledoc """
  A bonus feature (featurette, behind-the-scenes, deleted scene) belonging to
  a movie, TV series, movie series, or season. Extras live in subdirectories
  like `Extras/` alongside the main media files and are serialized as
  `hasPart` -> `VideoObject` entries.

  The owner of an extra is identified by the discriminator pair
  `(owner_type, owner_id)`. `owner_type` is one of `:movie`, `:tv_series`,
  `:movie_series`, `:season`. No uniqueness constraint — multiple extras
  per container is legitimate.

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

  @owner_types [:movie, :tv_series, :movie_series, :season]

  schema "library_extras" do
    field :name, :string
    field :content_url, :string
    field :position, :integer
    field :owner_type, Ecto.Enum, values: @owner_types
    field :owner_id, Ecto.UUID

    has_many :files, MediaCentarr.Library.ExtraFile

    timestamps()
  end

  def owner_types, do: @owner_types

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :content_url, :position, :owner_type, :owner_id])
    |> validate_required([:owner_type, :owner_id])
  end
end
