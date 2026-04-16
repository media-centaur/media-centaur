defmodule MediaCentarr.ReleaseTracking.Item do
  @moduledoc """
  A movie or TV series being tracked for upcoming releases.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "release_tracking_items" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    field :status, Ecto.Enum, values: [:watching, :ignored], default: :watching
    field :source, Ecto.Enum, values: [:library, :manual], default: :library
    field :library_entity_id, Ecto.UUID
    field :last_refreshed_at, :utc_datetime
    field :poster_path, :string
    field :backdrop_path, :string
    field :last_library_season, :integer, default: 0
    field :last_library_episode, :integer, default: 0
    field :dismiss_released_before, :date

    has_many :releases, MediaCentarr.ReleaseTracking.Release
    has_many :events, MediaCentarr.ReleaseTracking.Event

    timestamps()
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :tmdb_id,
      :media_type,
      :name,
      :status,
      :source,
      :library_entity_id,
      :last_refreshed_at,
      :poster_path,
      :last_library_season,
      :last_library_episode
    ])
    |> validate_required([:tmdb_id, :media_type, :name])
    |> unique_constraint([:tmdb_id, :media_type],
      name: "release_tracking_items_tmdb_id_media_type_index"
    )
  end

  def update_changeset(item, attrs) do
    item
    |> cast(attrs, [
      :name,
      :status,
      :library_entity_id,
      :last_refreshed_at,
      :poster_path,
      :backdrop_path,
      :last_library_season,
      :last_library_episode,
      :dismiss_released_before
    ])
  end
end
