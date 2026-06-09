defmodule MediaCentaur.Acquisition.Plans.PlanUnit do
  @moduledoc """
  Schema for one wanted thing inside a draft plan — the plan-side
  sibling of `Pursuits.Unit` (ADR-055 vocabulary: a *unit*), carrying
  its discovery status and, once the planner has solved, its
  *assignment* (the chosen candidate, denormalized for display and
  commit-time rehydration).

  ## Status

      pending ──► found     (planner assigned a candidate)
              └─► unfound   (nothing acceptable covers it — a search
                             result, never a pursuit leaf)
      any     ──► excluded  (user opt-out at feedback time)

  `excluded_release_guids` accumulates per-unit "not this release"
  feedback; the runner applies the plan-wide union when re-solving
  (a release the user rejected for one episode is almost never what
  they want for another).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @statuses ~w(pending found unfound excluded)

  schema "acquisition_plan_units" do
    field :plan_id, Ecto.UUID
    field :season_number, :integer
    field :episode_number, :integer
    field :label, :string
    field :position, :integer, default: 0
    field :status, :string, default: "pending"
    field :assigned_guid, :string
    field :assigned_title, :string
    field :assigned_term, :string
    field :assigned_quality, :string
    field :assigned_seeders, :integer
    field :assigned_scope, :string
    field :excluded_release_guids, {:array, :string}, default: []

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Builds a new pending unit for a plan."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:plan_id, :season_number, :episode_number, :label, :position])
    |> validate_required([:plan_id, :label])
  end

  @doc "Records the planner's assignment and marks the unit found."
  def assign_changeset(%__MODULE__{} = unit, attrs) do
    unit
    |> cast(attrs, [
      :assigned_guid,
      :assigned_title,
      :assigned_term,
      :assigned_quality,
      :assigned_seeders,
      :assigned_scope
    ])
    |> validate_required([:assigned_guid, :assigned_title])
    |> put_change(:status, "found")
  end

  @doc "Marks the unit unfound and clears any stale assignment."
  def unfound_changeset(%__MODULE__{} = unit) do
    clear_assignment(unit, "unfound")
  end

  @doc """
  Records "not this release" feedback: appends the guid to the unit's
  exclusions and resets it to pending for the next solve.
  """
  def exclude_release_changeset(%__MODULE__{} = unit, guid) when is_binary(guid) do
    exclusions = Enum.uniq(unit.excluded_release_guids ++ [guid])

    unit
    |> clear_assignment("pending")
    |> put_change(:excluded_release_guids, exclusions)
  end

  @doc "User opt-out: the unit stays visible but the plan stops wanting it."
  def exclude_unit_changeset(%__MODULE__{} = unit) do
    clear_assignment(unit, "excluded")
  end

  defp clear_assignment(unit, status) when status in @statuses do
    change(unit,
      status: status,
      assigned_guid: nil,
      assigned_title: nil,
      assigned_term: nil,
      assigned_quality: nil,
      assigned_seeders: nil,
      assigned_scope: nil
    )
  end
end
