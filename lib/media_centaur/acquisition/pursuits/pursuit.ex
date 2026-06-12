defmodule MediaCentaur.Acquisition.Pursuits.Pursuit do
  @moduledoc """
  Schema for the pursuit aggregate row — the durable intent.

  A pursuit owns the *goal* ("get S01E03 of Sample Show at 1080p") and
  the *recipe* (how to search for it). Since ADR-055 the pursuit is a
  **composite**: the wanted things live as `Pursuits.Unit` children,
  each carrying its own attempt thread (current target, tried releases,
  decision flag, download observations). The parent row holds only the
  goal and an **outcome state** folded from its units
  (`Pursuits.State.fold_units/1`); progress is always *units satisfied
  / units wanted*.

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
    where the user picks. Each unit's concrete query lives on the unit.

  `tmdb_id` and `tmdb_type` are nullable: a `prowlarr_query` pursuit
  holds neither.

  ## State

  `Acquisition.Pursuits.State` is the single source of truth for the
  state strings. The parent state is written only by
  `Commands.Refold` (via `fold_changeset/2`) so it can never disagree
  with the units. Whether the pursuit is waiting on user input is a
  *unit-level* fact (`Unit.awaiting_decision_at`) — pursuit-level
  "awaiting decision" means "any unit awaiting" and is computed on
  read.

  ## Pillar placement (ADR-041)

  Pillar 1 (Long-term storage). State and recipe must survive restart
  so the watcher and timeline reconstruct correctly across in-place
  updates.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.Acquisition.Pursuits.State

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

    # Last observed (state, health) of the pursuit's tracked torrent —
    # written only by `Observations.observe_pursuit!/4` to detect
    # lifecycle transitions across Watcher ticks. Pursuit-level because
    # the torrent is a pursuit-level fact: every unit of a composite
    # pursuit shares it, so observing per-unit multiplied timeline
    # events by the unit count.
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
  Applies the unit-state fold to the parent (ADR-055). The only write
  path for `state` — used exclusively by `Commands.Refold`. A change
  is valid only from an in-flight state; terminal pursuits don't
  refold (re-arming semantics are a campaign Phase 1c concern).
  """
  def fold_changeset(%__MODULE__{state: current} = pursuit, new_state) do
    cond do
      new_state == current ->
        change(pursuit)

      current in State.in_flight() and new_state in State.all() ->
        change(pursuit, state: new_state)

      true ->
        pursuit
        |> change()
        |> add_error(
          :state,
          "cannot fold from #{current} to #{new_state}",
          valid_from: State.in_flight()
        )
    end
  end
end
