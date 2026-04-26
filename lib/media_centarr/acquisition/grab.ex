defmodule MediaCentarr.Acquisition.Grab do
  @moduledoc """
  Tracks an automated acquisition attempt for a TMDB item.

  One row per `(tmdb_id, tmdb_type, season_number, episode_number)` tuple.
  Movies use `(tmdb_id, "movie", nil, nil)`. TV episodes use a non-nil
  `season_number` and `episode_number`. Season packs use a non-nil
  `season_number` with a nil `episode_number`.

  ## Status lifecycle

      searching ─┬─► grabbed   (Prowlarr accepted the release)
                 ├─► snoozed   (no acceptable result; SearchAndGrab will retry)
                 ├─► abandoned (max attempts reached without success)
                 └─► cancelled (item removed, file appeared in library, or user disabled)

  Terminal states: grabbed, abandoned, cancelled. The `SearchAndGrab` worker
  reads the row on every wake and exits cleanly when it finds a terminal state.

  ## Attempt accounting

  - `attempt_count` increments on every "no acceptable result" outcome.
    Prowlarr-down outcomes do NOT increment — the search infrastructure
    being unavailable shouldn't burn the patience budget.
  - `last_attempt_at` and `last_attempt_outcome` capture the most recent
    attempt regardless of whether it bumped `attempt_count`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "acquisition_grabs" do
    field :tmdb_id, :string
    field :tmdb_type, :string
    field :title, :string
    field :year, :integer
    field :season_number, :integer
    field :episode_number, :integer
    field :status, :string, default: "searching"
    field :quality, :string
    field :attempt_count, :integer, default: 0
    field :grabbed_at, :utc_datetime
    field :last_attempt_at, :utc_datetime
    field :last_attempt_outcome, :string
    field :cancelled_at, :utc_datetime
    field :cancelled_reason, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :tmdb_id,
      :tmdb_type,
      :title,
      :year,
      :season_number,
      :episode_number
    ])
    |> validate_required([:tmdb_id, :tmdb_type, :title])
    |> unique_constraint([:tmdb_id, :tmdb_type, :season_number, :episode_number],
      name: :acquisition_grabs_tmdb_season_episode_index
    )
  end

  def grabbed_changeset(grab, quality) do
    now = DateTime.utc_now(:second)

    change(grab,
      status: "grabbed",
      quality: quality,
      grabbed_at: now,
      last_attempt_at: now,
      last_attempt_outcome: "grabbed"
    )
  end

  @doc """
  Records a failed-attempt outcome that should bump `attempt_count`.

  Used for "no results" and "no acceptable quality" outcomes — the kind of
  miss that consumes the patience budget toward eventual abandonment.
  """
  def attempt_changeset(grab, outcome, opts \\ []) do
    snoozed = Keyword.get(opts, :snoozed, false)
    next_status = if snoozed, do: "snoozed", else: grab.status

    change(grab,
      status: next_status,
      attempt_count: grab.attempt_count + 1,
      last_attempt_at: DateTime.utc_now(:second),
      last_attempt_outcome: outcome
    )
  end

  @doc """
  Records an attempt outcome WITHOUT bumping `attempt_count`.

  Used when the failure is on the search infrastructure (Prowlarr down,
  network error) — we still want to record the attempt for visibility but
  shouldn't penalise the grab toward abandonment.
  """
  def infrastructure_failure_changeset(grab, outcome) do
    change(grab,
      status: "snoozed",
      last_attempt_at: DateTime.utc_now(:second),
      last_attempt_outcome: outcome
    )
  end

  def abandoned_changeset(grab) do
    change(grab,
      status: "abandoned",
      cancelled_at: DateTime.utc_now(:second),
      cancelled_reason: "abandoned"
    )
  end

  def cancelled_changeset(grab, reason) when is_binary(reason) do
    change(grab,
      status: "cancelled",
      cancelled_at: DateTime.utc_now(:second),
      cancelled_reason: reason
    )
  end
end
