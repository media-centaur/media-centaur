defmodule MediaCentarr.Acquisition.Pursuits.Pursuit do
  @moduledoc """
  Schema for the pursuit aggregate row — the durable intent.

  A pursuit owns the *goal* ("get S01E03 of Sample Show at 1080p") and
  the *recipe* (how to search for it) across many target attempts. The
  recipe lives on the pursuit so it survives the failure of any single
  target.

  ## Recipe (`recipe_type`)

  Tagged at the column level:

  - `recipe_type = "tmdb"` — TMDB-typed lookup. Reads `tmdb_id`,
    `tmdb_type ∈ {"movie","tv"}`, plus optional `season_number`,
    `episode_number`, `year`. Used by the auto-acquisition path; the
    worker can `TitleMatcher`-filter Prowlarr results and auto-grab.
  - `recipe_type = "prowlarr_query"` — free-form Prowlarr query string.
    Reads `manual_query` (brace syntax allowed; expanded by
    `Acquisition.QueryExpander`). The worker can't auto-match against
    canonical metadata, so results route through the decision card
    where the user picks.

  `tmdb_id` and `tmdb_type` are nullable: a `prowlarr_query` pursuit
  holds neither.

  ## State transitions

  Named per-transition changesets, each validating the source state.
  `Acquisition.Pursuits.State` is the single source of truth for
  which state strings exist.

  Whether the pursuit is waiting on user input is encoded *orthogonally*
  as `awaiting_decision_at :utc_datetime` — set by
  `Commands.RequestDecision`, cleared by `Commands.PickTarget` /
  `Commands.ChangeTarget` / terminal-transition commands. The flag
  doesn't change `state`; the pursuit is still `active`, just blocked.

  ## Pillar placement (ADR-041)

  Pillar 1 (Long-term storage). State, recipe, attempt history, and
  observation timestamps must survive restart so the watcher and
  timeline reconstruct correctly across in-place updates.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentarr.Acquisition.Pursuits.State

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  @origins ~w(auto manual)
  @recipe_types ~w(tmdb prowlarr_query)
  @tmdb_types ~w(movie tv)

  schema "acquisition_pursuits" do
    field :state, :string, default: "active"
    field :origin, :string

    field :recipe_type, :string, default: "tmdb"
    # TMDB recipe fields (populated when recipe_type = "tmdb").
    field :tmdb_id, :string
    field :tmdb_type, :string
    field :year, :integer
    field :season_number, :integer
    field :episode_number, :integer
    # Prowlarr-query recipe field (populated when recipe_type = "prowlarr_query").
    field :manual_query, :string

    field :title, :string
    field :criteria, :map, default: %{}
    field :tried_release_guids, {:array, :string}, default: []
    field :attempt_count, :integer, default: 0
    field :current_target_id, Ecto.UUID
    field :awaiting_decision_at, :utc_datetime
    field :stall_first_seen_at, :utc_datetime
    field :zero_seeders_first_seen_at, :utc_datetime
    field :last_queue_state, :string
    field :last_queue_health, :string

    timestamps()
  end

  @type t :: %__MODULE__{}
  @type recipe_type :: :tmdb | :prowlarr_query

  @cast_fields ~w(
    recipe_type tmdb_id tmdb_type title year season_number episode_number
    origin manual_query criteria
  )a

  @doc """
  Builds a new pursuit. The `recipe_type` discriminator drives which
  recipe-level fields are required:

  - `recipe_type = "tmdb"` requires `tmdb_id`, `tmdb_type ∈ {"movie","tv"}`.
  - `recipe_type = "prowlarr_query"` requires `manual_query`.

  Both require `title` and `origin`.
  """
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @cast_fields)
    |> validate_required([:title, :origin, :recipe_type])
    |> validate_inclusion(:origin, @origins)
    |> validate_inclusion(:recipe_type, @recipe_types)
    |> validate_recipe_fields()
  end

  defp validate_recipe_fields(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_recipe_fields(changeset) do
    case get_field(changeset, :recipe_type) do
      "tmdb" ->
        changeset
        |> validate_required([:tmdb_id, :tmdb_type])
        |> validate_inclusion(:tmdb_type, @tmdb_types)

      "prowlarr_query" ->
        validate_required(changeset, [:manual_query])

      _ ->
        changeset
    end
  end

  @doc """
  Sets `awaiting_decision_at` on a pursuit. State is unchanged — the
  pursuit is still `active`, just blocked on user input. Idempotent;
  calling with an already-set timestamp leaves the original value.
  """
  def set_awaiting_decision_changeset(%__MODULE__{awaiting_decision_at: nil} = pursuit, now) do
    change(pursuit, awaiting_decision_at: DateTime.truncate(now, :second))
  end

  def set_awaiting_decision_changeset(%__MODULE__{} = pursuit, _now), do: change(pursuit)

  @doc "Clears `awaiting_decision_at` (user picked, command moved on, etc.)."
  def clear_awaiting_decision_changeset(%__MODULE__{} = pursuit) do
    change(pursuit, awaiting_decision_at: nil)
  end

  @doc "Closes a pursuit on verified arrival. Clears any pending awaiting-decision flag."
  def satisfy_changeset(%__MODULE__{} = pursuit) do
    pursuit
    |> change_state("satisfied", from: State.in_flight())
    |> put_change(:awaiting_decision_at, nil)
  end

  @doc "Closes a pursuit at give-up time. Clears any pending awaiting-decision flag."
  def exhaust_changeset(%__MODULE__{} = pursuit) do
    pursuit
    |> change_state("exhausted", from: State.in_flight())
    |> put_change(:awaiting_decision_at, nil)
  end

  @doc "Closes a pursuit by user request. Clears any pending awaiting-decision flag."
  def cancel_changeset(%__MODULE__{} = pursuit) do
    pursuit
    |> change_state("cancelled", from: State.in_flight())
    |> put_change(:awaiting_decision_at, nil)
  end

  @doc """
  Records a target attempt against this pursuit. Always bumps
  `attempt_count`. Appends `release_guid` to `tried_release_guids` when
  non-nil and not already present.
  """
  def record_attempt_changeset(%__MODULE__{} = pursuit, release_guid) do
    base = change(pursuit, attempt_count: pursuit.attempt_count + 1)

    case release_guid do
      nil -> base
      guid when is_binary(guid) -> maybe_append_guid(base, pursuit.tried_release_guids, guid)
    end
  end

  @doc "Sets `current_target_id` (nullable — `nil` clears it)."
  def set_current_target_changeset(%__MODULE__{} = pursuit, target_id) do
    change(pursuit, current_target_id: target_id)
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
