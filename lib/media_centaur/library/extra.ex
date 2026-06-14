defmodule MediaCentaur.Library.Extra do
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
  playable path; ExtraFile rows record which media directory the file
  was seen in. `Library.Inbound` writes the ExtraFile alongside the Extra
  on ingest; pre-existing extras are backfilled by
  `Library.backfill_extra_files/0` on boot.
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

    has_many :files, MediaCentaur.Library.ExtraFile

    timestamps()
  end

  def owner_types, do: @owner_types

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :content_url, :position, :owner_type, :owner_id])
    |> validate_required([:owner_type, :owner_id])
  end

  @doc """
  Changeset for re-deriving an extra's display name from its file path. Trims
  surrounding whitespace and enforces the writer-level invariant that a derived
  name is never blank — so no re-derive pass can replace a name with nothing.
  """
  def update_name_changeset(%__MODULE__{} = extra, attrs) do
    extra
    |> cast(attrs, [:name])
    |> update_change(:name, &trim_to_nil/1)
    |> validate_required([:name])
  end

  defp trim_to_nil(nil), do: nil

  defp trim_to_nil(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
