defmodule MediaCentaur.Library.Identifier do
  @moduledoc """
  An external identifier linking an entity to a third-party service
  (TMDB, IMDB, etc.). Modelled as a schema.org `PropertyValue`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_identifiers" do
    field :property_id, :string
    field :value, :string

    belongs_to :entity, MediaCentaur.Library.Entity

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:property_id, :value, :entity_id])
    |> validate_required([:property_id, :value, :entity_id])
  end
end
