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
    field :in_library_at, :utc_datetime
    field :release_type, :string
    # The film's own TMDB id for movie/collection rows (nil for TV rows) —
    # the unit identity the want ledger keys movie wants on (ADR-056).
    field :part_tmdb_id, :integer

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
      :release_type,
      :part_tmdb_id,
      :item_id
    ])
    |> validate_required([:item_id])
    |> unique_constraint(:item_id,
      name: :release_tracking_releases_identity_index,
      message: "duplicate release for this item/season/episode/type"
    )
  end
end
