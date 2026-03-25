defmodule MediaCentaur.Library.Season do
  @moduledoc """
  A TV season belonging to a `TVSeries` entity. Created from TMDB season data
  when a file for that season is first ingested.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "seasons" do
    field :season_number, :integer
    field :number_of_episodes, :integer
    field :name, :string

    belongs_to :entity, MediaCentaur.Library.Entity
    has_many :episodes, MediaCentaur.Library.Episode
    has_many :extras, MediaCentaur.Library.Extra

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:season_number, :number_of_episodes, :name, :entity_id])
  end
end
