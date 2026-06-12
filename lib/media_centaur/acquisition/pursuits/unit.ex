defmodule MediaCentaur.Acquisition.Pursuits.Unit do
  @moduledoc """
  Schema for one wanted thing inside a pursuit — the carrier of the
  attempt thread ([ADR-055](../../../../decisions/architecture/2026-06-09-055-composite-pursuits.md)).

  A pursuit is a composite: the parent row holds the goal (recipe,
  title, criteria) while each unit holds one wanted thing (an episode,
  a movie, or one expanded query) together with its attempt thread —
  the current target, tried releases, decision flag, and download
  observations. A target (one grab attempt of one release) covers ≥1
  units via `Pursuits.TargetUnit`; progress is always *units
  satisfied / units wanted*, never a count of targets.

  ## State transitions

  The unit state machine is the pre-composite pursuit state machine,
  moved down one level:

      active ─┬─► satisfied  (a covering release landed & verified)
              ├─► exhausted  (no acceptable alternatives left)
              └─► cancelled  (user)

  Whether the unit is waiting on user input is encoded orthogonally as
  `awaiting_decision_at` — exactly the old pursuit-level flag.
  `Acquisition.Pursuits.UnitState` is the single source of truth for
  the state strings.

  ## Pillar placement (ADR-041)

  Pillar 1 (Long-term storage) — thread state must survive restart so
  the watcher and timeline reconstruct correctly.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.Acquisition.Pursuits.UnitState

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "acquisition_pursuit_units" do
    field :pursuit_id, Ecto.UUID
    field :state, :string, default: "active"
    # Stable ordering inside the composite (brace-expansion order,
    # episode order). Display-only; no uniqueness guarantee.
    field :position, :integer, default: 0
    # Display name for the unit ("S01E03", an expanded query). Nullable —
    # a single-unit pursuit renders the pursuit title instead.
    field :label, :string
    # The concrete search query for this unit (query-door pursuits).
    # Nullable — TMDB-recipe units derive queries from the parent recipe.
    field :query, :string
    # TMDB-door unit identity (media-search campaign Phase 3): which
    # episode this unit wants. Nullable — query-door units are
    # identified by their term, movies by the parent recipe.
    field :season_number, :integer
    field :episode_number, :integer

    field :current_target_id, Ecto.UUID
    field :tried_release_guids, {:array, :string}, default: []
    field :attempt_count, :integer, default: 0
    field :awaiting_decision_at, :utc_datetime
    field :stall_first_seen_at, :utc_datetime
    field :zero_seeders_first_seen_at, :utc_datetime

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Builds a new unit in `active` state for a pursuit."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:pursuit_id, :label, :query, :position, :season_number, :episode_number])
    |> validate_required([:pursuit_id])
  end

  @doc """
  Sets `awaiting_decision_at` on a unit. State is unchanged — the unit
  is still `active`, just blocked on user input. Idempotent; calling
  with an already-set timestamp leaves the original value.
  """
  def set_awaiting_decision_changeset(%__MODULE__{awaiting_decision_at: nil} = unit, now) do
    change(unit, awaiting_decision_at: DateTime.truncate(now, :second))
  end

  def set_awaiting_decision_changeset(%__MODULE__{} = unit, _now), do: change(unit)

  @doc "Clears `awaiting_decision_at` (user picked, command moved on, etc.)."
  def clear_awaiting_decision_changeset(%__MODULE__{} = unit) do
    change(unit, awaiting_decision_at: nil)
  end

  @doc "Closes a unit on verified arrival. Clears any pending awaiting-decision flag."
  def satisfy_changeset(%__MODULE__{} = unit) do
    unit
    |> change_state("satisfied", from: UnitState.in_flight())
    |> put_change(:awaiting_decision_at, nil)
  end

  @doc "Closes a unit at give-up time. Clears any pending awaiting-decision flag."
  def exhaust_changeset(%__MODULE__{} = unit) do
    unit
    |> change_state("exhausted", from: UnitState.in_flight())
    |> put_change(:awaiting_decision_at, nil)
  end

  @doc "Closes a unit by user request. Clears any pending awaiting-decision flag."
  def cancel_changeset(%__MODULE__{} = unit) do
    unit
    |> change_state("cancelled", from: UnitState.in_flight())
    |> put_change(:awaiting_decision_at, nil)
  end

  @doc """
  Records a target attempt against this unit. Always bumps
  `attempt_count`. Appends `release_guid` to `tried_release_guids` when
  non-nil and not already present.
  """
  def record_attempt_changeset(%__MODULE__{} = unit, release_guid) do
    base = change(unit, attempt_count: unit.attempt_count + 1)

    case release_guid do
      nil -> base
      guid when is_binary(guid) -> maybe_append_guid(base, unit.tried_release_guids, guid)
    end
  end

  @doc "Sets `current_target_id` (nullable — `nil` clears it)."
  def set_current_target_changeset(%__MODULE__{} = unit, target_id) do
    change(unit, current_target_id: target_id)
  end

  defp maybe_append_guid(changeset, existing_guids, guid) do
    if guid in existing_guids do
      changeset
    else
      put_change(changeset, :tried_release_guids, existing_guids ++ [guid])
    end
  end

  defp change_state(%__MODULE__{state: current} = unit, new_state, from: allowed_from) do
    if current in allowed_from do
      change(unit, state: new_state)
    else
      unit
      |> change()
      |> add_error(
        :state,
        "cannot transition from #{current} to #{new_state}",
        valid_from: allowed_from
      )
    end
  end
end
