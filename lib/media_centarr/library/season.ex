defmodule MediaCentarr.Library.Season do
  @moduledoc """
  A TV season belonging to a `TVSeries` entity. Created from TMDB season data
  when a file for that season is first ingested.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_seasons" do
    field :season_number, :integer
    field :number_of_episodes, :integer
    field :name, :string

    belongs_to :tv_series, MediaCentarr.Library.TVSeries
    has_many :episodes, MediaCentarr.Library.Episode

    # Polymorphic association — Extra rows discriminate on
    # `(owner_type, owner_id)` (Library Schema v2 Phase 2 Task E).
    has_many :extras, MediaCentarr.Library.Extra,
      foreign_key: :owner_id,
      where: [owner_type: :season]

    timestamps()
  end

  def create_changeset(attrs) do
    cast(%__MODULE__{}, attrs, [:season_number, :number_of_episodes, :name, :tv_series_id])
  end
end
