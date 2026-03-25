defmodule MediaCentaur.Library.Extra do
  @moduledoc """
  A bonus feature (featurette, behind-the-scenes, deleted scene) belonging to
  a movie `Entity`. Extras live in subdirectories like `Extras/` alongside
  the main movie file and are serialized as `hasPart` -> `VideoObject` entries.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "extras" do
    field :name, :string
    field :content_url, :string
    field :position, :integer

    belongs_to :entity, MediaCentaur.Library.Entity
    belongs_to :season, MediaCentaur.Library.Season

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :content_url, :position, :entity_id, :season_id])
  end
end
