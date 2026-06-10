defmodule MediaCentaur.Acquisition.Plans.Plan do
  @moduledoc """
  Schema for the durable draft plan (media-search campaign Phase 3) —
  one media-search request from targeting through approval.

  ## Lifecycle

      planning ──► ready ──┬─► committed   (became a composite pursuit)
         │                 └─► discarded   (user walked away)
         └─► discarded

  `planning` covers the autonomous search-and-solve phase (the RunPlan
  job); `ready` is the awaiting-approval state where the user steers
  (swap / exclude / re-search); nothing grabs until `committed`
  (campaign decision: plan-before-pursue). The row is durable from the
  moment planning starts — a refresh or restart mid-planning loses
  nothing (design decision 2026-06-09) — and `pursuit_id` is the
  committed pursuit's provenance pointer.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @statuses ~w(planning ready committed discarded)
  @tmdb_types ~w(movie tv)
  @origins ~w(manual tracking)

  schema "acquisition_plans" do
    field :status, :string, default: "planning"
    field :tmdb_id, :string
    field :tmdb_type, :string
    field :title, :string
    field :year, :integer
    field :criteria, :map, default: %{}
    field :grab_future, :boolean, default: false
    field :pursuit_id, Ecto.UUID
    field :error, :string
    # "manual" = media-search door; "tracking" = release-tracking drop
    # plan (ADR-056). tracking_item_id is the back-pointer to the
    # ReleaseTracking.Item — required for cancel-dismisses and the
    # one-active-draft-per-title rule (the tmdb id alone can't find the
    # item for collection parts).
    field :origin, :string, default: "manual"
    field :tracking_item_id, Ecto.UUID

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Builds a new plan in `planning`."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :tmdb_id,
      :tmdb_type,
      :title,
      :year,
      :criteria,
      :grab_future,
      :origin,
      :tracking_item_id
    ])
    |> validate_required([:tmdb_id, :tmdb_type, :title])
    |> validate_inclusion(:tmdb_type, @tmdb_types)
    |> validate_inclusion(:origin, @origins)
  end

  @doc "Transitions the plan's status, validating the source state."
  def transition_changeset(%__MODULE__{status: current} = plan, new_status, allowed_from) do
    if new_status in @statuses and current in allowed_from do
      plan
      |> change(status: new_status)
      |> put_change(:error, nil)
    else
      plan
      |> change()
      |> add_error(:status, "cannot transition from #{current} to #{new_status}")
    end
  end

  @doc "Records a planning failure without leaving `planning` silently stuck."
  def error_changeset(%__MODULE__{} = plan, reason) when is_binary(reason) do
    change(plan, error: reason)
  end

  @doc "Stamps the committed pursuit's id (provenance)."
  def committed_changeset(%__MODULE__{} = plan, pursuit_id) do
    plan
    |> transition_changeset("committed", ["ready"])
    |> put_change(:pursuit_id, pursuit_id)
  end
end
