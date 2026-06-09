defmodule MediaCentaur.Acquisition.Pursuits.TargetUnit do
  @moduledoc """
  Join schema: which units a target's release covers.

  A target is one grab attempt of one *release*; a release may cover
  many units (a season pack covers every episode it contains —
  [ADR-055](../../../../decisions/architecture/2026-06-09-055-composite-pursuits.md)).
  This join is deliberately a table rather than a `unit_id` FK on
  targets so pack coverage (campaign Phase 2) is a data change, not a
  schema retrofit. Until packs land, every target covers exactly one
  unit.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "acquisition_target_units" do
    field :target_id, Ecto.UUID
    field :unit_id, Ecto.UUID

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Links a target to one unit it covers."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:target_id, :unit_id])
    |> validate_required([:target_id, :unit_id])
    |> unique_constraint([:target_id, :unit_id])
  end
end
