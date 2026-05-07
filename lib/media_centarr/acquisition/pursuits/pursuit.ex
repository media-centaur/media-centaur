defmodule MediaCentarr.Acquisition.Pursuits.Pursuit do
  @moduledoc """
  Schema for the pursuit aggregate row.

  A pursuit owns the goal — "get S01E03 of Sample Show at 1080p" — across
  multiple grab attempts. Identification is TMDB-keyed (matching the `Grab`
  schema) so a pursuit can exist before any library entity is created.

  State transitions are exposed as named per-transition changesets, each
  validating the source state. The `Acquisition.Pursuits.State` module is
  the single source of truth for which state strings exist.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentarr.Acquisition.Pursuits.State

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @origins ~w(auto manual)

  schema "acquisition_pursuits" do
    field :state, :string, default: "active"
    field :origin, :string
    field :tmdb_id, :string
    field :tmdb_type, :string
    field :title, :string
    field :year, :integer
    field :season_number, :integer
    field :episode_number, :integer
    field :criteria, :map, default: %{}
    field :tried_release_guids, {:array, :string}, default: []
    field :attempt_count, :integer, default: 0
    field :stall_first_seen_at, :utc_datetime
    field :zero_seeders_first_seen_at, :utc_datetime

    timestamps()
  end

  @type t :: %__MODULE__{}

  @cast_fields ~w(
    tmdb_id tmdb_type title year season_number episode_number
    origin criteria
  )a

  @required_fields ~w(tmdb_id tmdb_type title origin)a

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:origin, @origins)
  end

  @doc "Transitions an in-flight pursuit to `needs_decision`."
  def request_decision_changeset(%__MODULE__{} = pursuit) do
    change_state(pursuit, "needs_decision", from: ["active"])
  end

  @doc "Transitions `needs_decision` back to `active` after the user picks an alternative."
  def resume_changeset(%__MODULE__{} = pursuit) do
    change_state(pursuit, "active", from: ["needs_decision"])
  end

  @doc "Closes a pursuit on verified arrival."
  def satisfy_changeset(%__MODULE__{} = pursuit) do
    change_state(pursuit, "satisfied", from: State.in_flight())
  end

  @doc "Closes a pursuit at give-up time (system or user)."
  def exhaust_changeset(%__MODULE__{} = pursuit) do
    change_state(pursuit, "exhausted", from: State.in_flight())
  end

  @doc "Closes a pursuit by user request."
  def cancel_changeset(%__MODULE__{} = pursuit) do
    change_state(pursuit, "cancelled", from: State.in_flight())
  end

  @doc """
  Records a grab attempt against this pursuit. Always bumps `attempt_count`.
  Appends `release_guid` to `tried_release_guids` when non-nil and not already
  present.
  """
  def record_attempt_changeset(%__MODULE__{} = pursuit, release_guid) do
    base = change(pursuit, attempt_count: pursuit.attempt_count + 1)

    case release_guid do
      nil -> base
      guid when is_binary(guid) -> maybe_append_guid(base, pursuit.tried_release_guids, guid)
    end
  end

  defp maybe_append_guid(changeset, existing_guids, guid) do
    if guid in existing_guids do
      changeset
    else
      put_change(changeset, :tried_release_guids, existing_guids ++ [guid])
    end
  end

  defp change_state(%__MODULE__{state: current} = pursuit, new_state, from: allowed_from) do
    if current in allowed_from do
      change(pursuit, state: new_state)
    else
      pursuit
      |> change()
      |> add_error(
        :state,
        "cannot transition from #{current} to #{new_state}",
        valid_from: allowed_from
      )
    end
  end
end
