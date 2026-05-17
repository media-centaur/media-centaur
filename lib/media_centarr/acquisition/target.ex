defmodule MediaCentarr.Acquisition.Target do
  @moduledoc """
  A specific release the pursuit is chasing — one attempt at acquiring
  the goal described by the pursuit's recipe.

  A pursuit has many targets over its lifetime (history of attempts);
  the current attempt is referenced from `pursuit.current_target_id`.
  The recipe and quality preferences live on the pursuit; the target
  only carries per-attempt facts.

  ## Status lifecycle

      seeking ─┬─► acquired  (Prowlarr accepted the release)
               ├─► failed    (max attempts reached without success,
               │              or the file never materialised at the
               │              download client and the user pivoted)
               └─► cancelled (item removed, file appeared in library,
                              or user disabled)

      acquired ─┬─► succeeded (file landed in the library)
                ├─► failed    (user pivots via ChangeTarget)
                └─► cancelled (user cancels the specific target)

  Terminal states: `succeeded`, `failed`, `cancelled`. The
  `PursueTarget` worker reads the row on every wake and exits cleanly
  when it finds a terminal state. Manual picks land directly in
  `acquired`.

  Snoozed-between-attempts is *not* a status value — Oban's
  `scheduled_at` on the worker job is the authoritative "when will we
  try again" signal. The target stays in `seeking` while the job is
  scheduled.

  ## Attempt accounting

  - `attempt_count` increments on every "no acceptable result" outcome.
    Prowlarr-down outcomes do NOT increment — the search infrastructure
    being unavailable shouldn't burn the patience budget.
  - `last_attempt_at` and `last_attempt_outcome` capture the most
    recent attempt regardless of whether it bumped `attempt_count`.

  ## Pillar placement (ADR-041)

  Pillar 1. Target lifecycle plainly needs durability — `seeking`,
  `acquired` must survive restart so the worker can pick up where it
  left off. Diagnostic fields (`last_attempt_at`,
  `last_attempt_outcome`) stay co-located for post-restart UX
  continuity on a desktop app that restarts for in-place updates.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MediaCentarr.Search.{Quality, SearchResult}

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "acquisition_targets" do
    field :pursuit_id, Ecto.UUID
    field :title, :string
    field :status, :string, default: "seeking"
    # When the worker will next wake up for this seeking target. Read by
    # PursuitStatus so the row can say "next attempt in 2h 15m" without
    # querying Oban. Written by PursueTarget in the same transaction
    # that schedules the snooze; nulled on terminal transitions.
    field :next_attempt_at, :utc_datetime
    # `quality` is the OUTCOME — captured tier of the actual acquired
    # release. The bounds live on the pursuit's recipe.
    field :quality, :string
    field :attempt_count, :integer, default: 0
    field :acquired_at, :utc_datetime
    field :last_attempt_at, :utc_datetime
    field :last_attempt_outcome, :string
    field :cancelled_at, :utc_datetime
    field :cancelled_reason, :string
    field :origin, :string, default: "auto"
    field :prowlarr_guid, :string
    field :release_title, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Builds a new target in `seeking` status for a pursuit."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:pursuit_id, :title, :origin])
    |> validate_required([:pursuit_id, :title])
    |> put_change(:status, "seeking")
  end

  @doc """
  Builds a target directly in `acquired` from a manual user pick — used
  by `Commands.PickTarget` after the user chooses a release from the
  decision card or the manual-search results.
  """
  @spec acquired_changeset(SearchResult.t(), keyword()) :: Ecto.Changeset.t()
  def acquired_changeset(%SearchResult{} = result, opts) do
    pursuit_id = Keyword.fetch!(opts, :pursuit_id)
    origin = Keyword.get(opts, :origin, "manual")
    now = DateTime.utc_now(:second)
    quality_label = Quality.label(result.quality)

    %__MODULE__{}
    |> cast(%{pursuit_id: pursuit_id, title: result.title, origin: origin}, [
      :pursuit_id,
      :title,
      :origin
    ])
    |> change(
      status: "acquired",
      quality: quality_label,
      release_title: result.title,
      prowlarr_guid: result.guid,
      acquired_at: now,
      last_attempt_at: now,
      last_attempt_outcome: "acquired",
      next_attempt_at: nil
    )
    |> validate_required([:pursuit_id, :title])
  end

  @doc """
  Transitions a `seeking` target to `acquired` after the auto-pick worker
  picks a release. Used by `Jobs.PursueTarget`.
  """
  def acquire_changeset(target, quality, release_title \\ nil, prowlarr_guid \\ nil) do
    now = DateTime.utc_now(:second)

    change(target,
      status: "acquired",
      quality: quality,
      release_title: release_title,
      prowlarr_guid: prowlarr_guid,
      acquired_at: now,
      last_attempt_at: now,
      last_attempt_outcome: "acquired",
      next_attempt_at: nil
    )
  end

  @doc """
  Records a failed-attempt outcome that should bump `attempt_count`.

  Used for "no results" and "no acceptable quality" outcomes — the kind
  of miss that consumes the patience budget toward eventual failure.
  """
  def attempt_changeset(target, outcome) do
    change(target,
      attempt_count: target.attempt_count + 1,
      last_attempt_at: DateTime.utc_now(:second),
      last_attempt_outcome: outcome
    )
  end

  @doc """
  Records an attempt outcome WITHOUT bumping `attempt_count`.

  Used when the failure is on the search infrastructure (Prowlarr
  down, network error) — we still want to record the attempt for
  visibility but shouldn't penalise the target toward failure.
  """
  def infrastructure_failure_changeset(target, outcome) do
    change(target,
      last_attempt_at: DateTime.utc_now(:second),
      last_attempt_outcome: outcome
    )
  end

  @doc "Terminal-failure transition for an exhausted target."
  def failed_changeset(target, reason \\ "abandoned") do
    change(target,
      status: "failed",
      cancelled_at: DateTime.utc_now(:second),
      cancelled_reason: reason,
      next_attempt_at: nil
    )
  end

  @doc "Terminal-success transition — the file landed and was matched."
  def succeeded_changeset(target) do
    change(target, status: "succeeded", next_attempt_at: nil)
  end

  @doc "User-driven cancellation of a specific target."
  def cancelled_changeset(target, reason) when is_binary(reason) do
    change(target,
      status: "cancelled",
      cancelled_at: DateTime.utc_now(:second),
      cancelled_reason: reason,
      next_attempt_at: nil
    )
  end

  @doc """
  Records when the next snooze will fire. Called by the PursueTarget
  worker right before it returns `{:snooze, seconds}` to Oban, so the
  target row stays in sync with the scheduled job's `scheduled_at`
  without the read path having to query Oban.
  """
  @spec schedule_next_attempt_changeset(t(), DateTime.t()) :: Ecto.Changeset.t()
  def schedule_next_attempt_changeset(%__MODULE__{} = target, %DateTime{} = next_attempt_at) do
    change(target, next_attempt_at: DateTime.truncate(next_attempt_at, :second))
  end
end
