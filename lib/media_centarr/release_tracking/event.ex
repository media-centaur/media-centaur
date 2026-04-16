defmodule MediaCentarr.ReleaseTracking.Event do
  @moduledoc """
  A denormalized log entry for release tracking changes. Self-contained —
  stores item_name directly so events survive item deletion.
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
        :removed_from_schedule,
        :new_season_announced,
        :new_episodes_announced,
        :began_tracking,
        :stopped_tracking
      ]

    field :description, :string
    field :item_name, :string
    field :metadata, :map, default: %{}
    field :item_id, Ecto.UUID

    timestamps(updated_at: false)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:event_type, :description, :item_name, :metadata, :item_id])
    |> validate_required([:event_type, :description, :item_name])
  end
end
