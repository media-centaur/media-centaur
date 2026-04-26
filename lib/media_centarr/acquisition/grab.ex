defmodule MediaCentarr.Acquisition.Grab do
  @moduledoc """
  Tracks an acquisition — automated or manual — for a single release.

  ## Origin

  - `origin: "auto"` — system-initiated from a release-tracker
    `{:release_ready, ...}` broadcast. Keyed
    `(tmdb_id, tmdb_type, season_number, episode_number)`. Goes through
    the `SearchAndGrab` Oban worker (search → snooze → grab/abandon).
  - `origin: "manual"` — user-submitted from the Downloads page search
    form. Keyed `(prowlarr_guid, "manual", nil, nil)` — i.e., the
    Prowlarr indexer GUID is reused as `tmdb_id` so the existing unique
    index gives us "don't double-grab the same release" idempotency for
    free, without making `tmdb_id` nullable. Inserted directly in
    terminal `"grabbed"` state — no Oban round-trip, manual grabs are
    atomic from the user's perspective.

  ## Status lifecycle (auto-origin only)

      searching ─┬─► grabbed   (Prowlarr accepted the release)
                 ├─► snoozed   (no acceptable result; SearchAndGrab will retry)
                 ├─► abandoned (max attempts reached without success)
                 └─► cancelled (item removed, file appeared in library, or user disabled)

  Terminal states: grabbed, abandoned, cancelled. The `SearchAndGrab` worker
  reads the row on every wake and exits cleanly when it finds a terminal state.
  Manual grabs land directly in `grabbed`.

  ## Attempt accounting

  - `attempt_count` increments on every "no acceptable result" outcome.
    Prowlarr-down outcomes do NOT increment — the search infrastructure
    being unavailable shouldn't burn the patience budget.
  - `last_attempt_at` and `last_attempt_outcome` capture the most recent
    attempt regardless of whether it bumped `attempt_count`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MediaCentarr.Acquisition.{Quality, SearchResult}

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
    # `quality` is the OUTCOME — captured tier of the actual grabbed
    # release. `min_quality` / `max_quality` are the BOUNDS — snapshot of
    # the effective preferences at enqueue time.
    field :quality, :string
    field :min_quality, :string
    field :max_quality, :string
    field :quality_4k_patience_hours, :integer
    field :attempt_count, :integer, default: 0
    field :grabbed_at, :utc_datetime
    field :last_attempt_at, :utc_datetime
    field :last_attempt_outcome, :string
    field :cancelled_at, :utc_datetime
    field :cancelled_reason, :string
    field :origin, :string, default: "auto"
    field :prowlarr_guid, :string
    field :manual_query, :string

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
      :episode_number,
      :min_quality,
      :max_quality,
      :quality_4k_patience_hours,
      :origin
    ])
    |> validate_required([:tmdb_id, :tmdb_type, :title])
    |> unique_constraint([:tmdb_id, :tmdb_type, :season_number, :episode_number],
      name: :acquisition_grabs_tmdb_season_episode_index
    )
  end

  @doc """
  Builds a row in terminal `"grabbed"` state from a manual user submission.

  `query` is the search string the user typed — stored on the row for
  the activity-list "where did this come from?" surface. Whitespace-only
  queries collapse to `nil`. The Prowlarr GUID doubles as `tmdb_id` so
  the unique index naturally prevents double-grabbing the same release.
  """
  @spec manual_grabbed_changeset(SearchResult.t(), String.t()) :: Ecto.Changeset.t()
  def manual_grabbed_changeset(%SearchResult{} = result, query) when is_binary(query) do
    now = DateTime.utc_now(:second)
    quality_label = Quality.label(result.quality)

    cleaned_query =
      case String.trim(query) do
        "" -> nil
        trimmed -> trimmed
      end

    %__MODULE__{}
    |> cast(
      %{
        tmdb_id: result.guid,
        tmdb_type: "manual",
        title: result.title,
        origin: "manual",
        prowlarr_guid: result.guid,
        manual_query: cleaned_query
      },
      [:tmdb_id, :tmdb_type, :title, :origin, :prowlarr_guid, :manual_query]
    )
    |> change(
      status: "grabbed",
      quality: quality_label,
      grabbed_at: now,
      last_attempt_at: now,
      last_attempt_outcome: "grabbed"
    )
    |> validate_required([:tmdb_id, :tmdb_type, :title, :origin])
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
