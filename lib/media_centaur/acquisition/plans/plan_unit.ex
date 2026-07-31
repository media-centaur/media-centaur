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
    # The episode's air date, denormalized from the want / selection at
    # plan creation so the cour-aware coverage guard can compare it
    # against a candidate's publish date at solve time (the runner
    # reloads units from the DB). Nil for movie units and legacy rows —
    # the guard no-ops on missing data.
    field :air_date, :date
    field :label, :string
    field :position, :integer, default: 0
    field :status, :string, default: "pending"
    field :assigned_guid, :string
    field :assigned_title, :string
    field :assigned_term, :string
    field :assigned_quality, :string
    field :assigned_seeders, :integer
    field :assigned_indexer_id, :integer
    field :assigned_size_bytes, :integer
    field :assigned_scope, :string
    # The fit-gated offer: an over-broad pack that *would* cover this
    # unit but brings far more than was wanted, so the planner set it
    # aside instead of grabbing it. Present only on `unfound` units that
    # have no right-sized release; the board spells out the over-grab and
    # the user can opt in (which assigns it like any swap). See `Planner`.
    field :offered_guid, :string
    field :offered_title, :string
    field :offered_scope, :string
    field :offered_size_bytes, :integer
    # How many identity-verified, non-bait releases exist below the
    # unit's quality floor when nothing acceptable was found — the
    # planner's "lower quality available" verdict, stamped at solve
    # time so the board's offer survives corpus expiry. The candidates
    # themselves are served live from the corpus (`Plans.alternatives_for/1`);
    # only the verdict is denormalized. 0 = a genuinely bare unfound.
    field :below_floor_count, :integer, default: 0
    field :excluded_release_guids, {:array, :string}, default: []
    # Per-unit quality floor override (nil = inherit the plan's
    # criteria). The patience elevation (ADR-056 Q4: `min := max`
    # inside a want's window) is stamped here at plan creation, so the
    # planner stays time-blind.
    field :min_quality, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc """
  Builds a new pending unit for a plan. `excluded_release_guids` may be
  seeded at creation — the drop planner pre-loads releases that already
  failed terminally for this unit (ADR-056 Q5 loop-breaker), so
  re-plans only ever assign genuinely new releases.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :plan_id,
      :season_number,
      :episode_number,
      :air_date,
      :label,
      :position,
      :min_quality,
      :excluded_release_guids
    ])
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
      :assigned_indexer_id,
      :assigned_size_bytes,
      :assigned_scope
    ])
    |> validate_required([:assigned_guid, :assigned_title])
    |> put_change(:status, "found")
    |> clear_offer()
  end

  @doc """
  Marks the unit unfound, clearing any stale assignment. With an `offer`
  map (`offered_guid`/`offered_title`/`offered_scope`/`offered_size_bytes`)
  the unit is unfound *but* carries the over-broad pack the user can opt
  into; `nil` clears any prior offer. `below_floor_count` carries the
  planner's "lower quality available" verdict (0 = bare unfound).
  """
  def unfound_changeset(%__MODULE__{} = unit, offer \\ nil, below_floor_count \\ 0) do
    unit
    |> clear_assignment("unfound")
    |> put_offer(offer)
    |> put_change(:below_floor_count, below_floor_count)
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
    unit
    |> change(
      status: status,
      assigned_guid: nil,
      assigned_title: nil,
      assigned_term: nil,
      assigned_quality: nil,
      assigned_seeders: nil,
      assigned_indexer_id: nil,
      assigned_scope: nil
    )
    |> clear_offer()
  end

  defp clear_offer(changeset) do
    change(changeset,
      offered_guid: nil,
      offered_title: nil,
      offered_scope: nil,
      offered_size_bytes: nil,
      below_floor_count: 0
    )
  end

  defp put_offer(changeset, nil), do: changeset

  defp put_offer(changeset, offer) when is_map(offer) do
    change(changeset,
      offered_guid: offer.offered_guid,
      offered_title: offer.offered_title,
      offered_scope: offer.offered_scope,
      offered_size_bytes: offer.offered_size_bytes
    )
  end
end
