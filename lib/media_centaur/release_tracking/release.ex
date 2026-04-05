defmodule MediaCentaur.ReleaseTracking.Release do
  @moduledoc """
  An individual upcoming release event — one row per episode or movie.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "release_tracking_releases" do
    field :air_date, :date
    field :title, :string
    field :season_number, :integer
    field :episode_number, :integer
    field :released, :boolean, default: false
    field :in_library, :boolean, default: false

    belongs_to :item, MediaCentaur.ReleaseTracking.Item

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :air_date,
      :title,
      :season_number,
      :episode_number,
      :released,
      :in_library,
      :item_id
    ])
    |> validate_required([:item_id])
  end

  def update_changeset(release, attrs) do
    release
    |> cast(attrs, [:air_date, :title, :released])
  end
end
