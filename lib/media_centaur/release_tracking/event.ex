defmodule MediaCentaur.ReleaseTracking.Event do
  @moduledoc """
  A notable change detected during TMDB refresh — date moved, new season, etc.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "release_tracking_events" do
    field :event_type, Ecto.Enum,
      values: [
        :upcoming_release_date_changed,
        :new_season_announced,
        :new_episodes_announced,
        :began_tracking,
        :stopped_tracking
      ]

    field :description, :string
    field :metadata, :map, default: %{}

    belongs_to :item, MediaCentaur.ReleaseTracking.Item

    timestamps(updated_at: false)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:event_type, :description, :metadata, :item_id])
    |> validate_required([:event_type, :description, :item_id])
  end
end
