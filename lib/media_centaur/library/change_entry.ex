defmodule MediaCentaur.Library.ChangeEntry do
  @moduledoc """
  A log entry recording a library change — an entity being added or removed.

  Stores a snapshot of the entity's name and type so removals remain visible
  after the entity is deleted. References entities only by UUID (no foreign key),
  so cascade deletes don't affect the log.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_change_entries" do
    field :entity_id, Ecto.UUID
    field :entity_name, :string
    field :entity_type, Ecto.Enum, values: [:movie, :movie_series, :tv_series, :video_object]
    field :kind, Ecto.Enum, values: [:added, :removed]

    timestamps(updated_at: false)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:entity_id, :entity_name, :entity_type, :kind])
    |> validate_required([:entity_id, :entity_name, :entity_type, :kind])
  end

  def backfill_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:entity_id, :entity_name, :entity_type, :kind, :inserted_at])
    |> validate_required([:entity_id, :entity_name, :entity_type, :kind, :inserted_at])
  end
end
