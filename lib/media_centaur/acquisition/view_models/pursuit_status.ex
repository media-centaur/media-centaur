defmodule MediaCentaur.Acquisition.ViewModels.PursuitStatus do
  @moduledoc """
  Display contract for the pursuit detail page.

  Built by `MediaCentaur.Acquisition.Pursuits.status_for/1` — joins the
  pursuit row with its unit, the unit's current target, and any
  matching download-client queue item, then routes through the pure
  `derive/4` function to produce `current_action`, `next_step`, and
  `available_actions`. The unit carries the attempt thread (ADR-055);
  the modal shows the sole unit's thread until the multi-unit
  drill-down lands.
  """

  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Unit}
  alias MediaCentaur.Acquisition.Pursuits.State
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Format

  alias MediaCentaur.Acquisition.ViewModels.{
    CurrentAction,
    DownloadProgress,
    NextStep,
    Recipe
  }

  alias MediaCentaur.Downloads.QueueItem

  @enforce_keys [
    :pursuit_id,
    :title,
    :state,
    :origin,
    :recipe,
    :current_action,
    :available_actions,
    :staleness
  ]
  defstruct [
    :pursuit_id,
    :title,
    :state,
    :origin,
    :recipe,
    :criteria_summary,
    :current_action,
    :next_step,
    :download,
    :staleness,
    :last_activity_at,
    # Loaded pursuit + unit + target structs are stashed so the
    # queue-tick refresh path (`Pursuits.refresh_status_download/2`) can
    # re-derive the dynamic fields against a fresh queue snapshot
    # without a DB round-trip. Not consumed by the template — purely a
    # memoisation handle for the refresh path.
    :pursuit,
    :unit,
    :target,
    available_actions: [],
    downloads: []
  ]

  @type action :: :cancel | :change_target | :request_decision
  @type staleness :: :fresh | :stale | :very_stale
  @type location :: :in_review | :none

  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          title: String.t(),
          state: State.t(),
          origin: :auto | :manual,
          recipe: Recipe.t(),
          criteria_summary: String.t() | nil,
          current_action: CurrentAction.t(),
          next_step: NextStep.t() | nil,
          download: DownloadProgress.t() | nil,
          downloads: [%{download: DownloadProgress.t(), release_title: String.t() | nil}],
          staleness: staleness(),
          last_activity_at: DateTime.t() | nil,
          available_actions: [action()],
          pursuit: Pursuit.t() | nil,
          unit: Unit.t() | nil,
          target: Target.t() | nil
        }

  @doc """
  Pure mapping from (pursuit, unit, target, queue_item) to the dynamic
  display fields. No DB, no PubSub. The unit carries the attempt thread
  (decision flag, attempt count — ADR-055); the target carries the
  per-release facts.

  The recipe lives on the pursuit and drives whether `ChangeTarget` is
  going to auto-pick or surface results for the user — but from the
  view-model's perspective, both recipes offer `:change_target` as the
  recovery action; the worker handles the divergence.
  """
  @spec derive(Pursuit.t(), Unit.t() | nil, Target.t() | nil, QueueItem.t() | nil) ::
          {CurrentAction.t(), NextStep.t() | nil, [action()]}
  def derive(%Pursuit{state: "satisfied"}, _unit, _target, _qi) do
    {
      %CurrentAction{
        verb: "Done",
        description: "File landed and identity verified.",
        severity: :success
      },
      nil,
      []
    }
  end

  def derive(%Pursuit{state: "partial"}, _unit, _target, _qi) do
    {
      %CurrentAction{
        verb: "Partially done",
        description: "Some of this pursuit landed; the rest didn't.",
        severity: :warning
      },
      nil,
      []
    }
  end

  def derive(%Pursuit{state: "exhausted"}, unit, _target, _qi) do
    attempt_count = (unit && unit.attempt_count) || 0

    {
      %CurrentAction{
        verb: "Gave up",
        description: "Exhausted after #{attempt_count} attempts.",
        severity: :error
      },
      %NextStep{description: "Start a new pursuit if you still want this."},
      []
    }
  end

  def derive(%Pursuit{state: "cancelled"}, _unit, _target, _qi) do
    {
      %CurrentAction{verb: "Cancelled", description: "Pursuit cancelled.", severity: :info},
      nil,
      []
    }
  end

  # Awaiting-decision takes precedence over the regular state:"active"
  # clauses. The unit is still active in lifecycle terms, but the
  # user-visible status is "we're blocked on your pick".
  def derive(%Pursuit{state: "active"}, %Unit{awaiting_decision_at: %DateTime{}}, _target, _qi) do
    {
      %CurrentAction{
        verb: "Decision needed",
        description: "Pick a release below.",
        severity: :warning
      },
      %NextStep{description: "Use the decision card below to pick or skip."},
      [:cancel]
    }
  end

  def derive(%Pursuit{state: "active"}, _unit, nil, _qi) do
    {
      %CurrentAction{
        verb: "Unknown",
        description: "Pursuit has no target — change target to begin.",
        severity: :warning
      },
      nil,
      [:cancel, :change_target]
    }
  end

  def derive(%Pursuit{state: "active"}, _unit, %Target{status: "seeking"} = t, _qi) do
    {
      %CurrentAction{
        verb: "Searching",
        description: searching_description(t),
        severity: :info
      },
      %NextStep{description: "Trying expanded queries — will pick the best match or snooze."},
      [:cancel, :request_decision]
    }
  end

  def derive(%Pursuit{state: "active"}, _unit, %Target{status: "failed"} = t, _qi) do
    {
      %CurrentAction{
        verb: "Stopped",
        description: "Auto-search gave up after #{t.attempt_count} attempts.",
        severity: :warning
      },
      %NextStep{description: "Change target or pick a release manually."},
      [:cancel, :change_target, :request_decision]
    }
  end

  def derive(%Pursuit{state: "active"}, _unit, %Target{status: "cancelled"}, _qi) do
    {
      %CurrentAction{
        verb: "Stopped",
        description: "Target was cancelled.",
        severity: :warning
      },
      %NextStep{description: "Change target to restart."},
      [:cancel, :change_target]
    }
  end

  def derive(
        %Pursuit{state: "active"},
        _unit,
        %Target{status: "acquired"},
        %QueueItem{state: qstate} = qi
      )
      when not is_nil(qstate), do: derive_acquired_in_queue(qi)

  def derive(%Pursuit{state: "active"}, _unit, %Target{status: "acquired"}, _qi) do
    {
      %CurrentAction{
        verb: "Downloaded",
        description: "Finished downloading — still importing, or already in your library.",
        severity: :info
      },
      %NextStep{
        description:
          "It may still be importing or already be in your library; change target to grab a different release."
      },
      [:cancel, :change_target]
    }
  end

  def derive(%Pursuit{state: "active"}, _unit, %Target{status: "succeeded"}, _qi) do
    {
      %CurrentAction{
        verb: "Done",
        description: "File landed and identity verified.",
        severity: :success
      },
      nil,
      []
    }
  end

  @doc """
  Location-aware variant. `location` distinguishes the post-download
  lifecycle stage of an `acquired` target that's no longer in the queue:
  `:in_review` (the file is sitting in the review queue) vs `:none`
  (no matching file in review or library yet). For every other case the
  location is irrelevant and this delegates to `derive/4`.
  """
  @spec derive(Pursuit.t(), Unit.t() | nil, Target.t() | nil, QueueItem.t() | nil, location()) ::
          {CurrentAction.t(), NextStep.t() | nil, [action()]}
  def derive(%Pursuit{state: "active"}, _unit, %Target{status: "acquired"}, nil, :in_review) do
    {
      %CurrentAction{
        verb: "In review",
        description: "Downloaded — waiting for you to approve the match in Review.",
        severity: :info
      },
      %NextStep{description: "Approve it in the Review queue to finish importing."},
      [:cancel]
    }
  end

  def derive(pursuit, unit, target, queue_item, _location), do: derive(pursuit, unit, target, queue_item)

  # The seeking-state description tells the user what to expect next.
  # When the worker has scheduled a snooze (`next_attempt_at` is set),
  # surface the countdown — the row reads "Next attempt in 2h 15m
  # (attempt 4)" instead of the timeless "Looking for an acceptable
  # release". Fresh targets (no schedule yet) fall through to the
  # original copy.
  defp searching_description(%Target{next_attempt_at: nil, attempt_count: n}),
    do: "Looking for an acceptable release (attempt #{n + 1})."

  defp searching_description(%Target{next_attempt_at: %DateTime{} = at, attempt_count: n}),
    do: "Next attempt #{Format.relative_in(at)} (attempt #{n + 1})."

  defp derive_acquired_in_queue(%QueueItem{state: :downloading} = qi) do
    {
      %CurrentAction{
        verb: "Downloading",
        description: download_description(qi),
        severity: :info
      },
      %NextStep{description: "When complete, the file watcher matches the title."},
      [:cancel]
    }
  end

  defp derive_acquired_in_queue(%QueueItem{state: :queued}) do
    {
      %CurrentAction{
        verb: "Queued",
        description: "Waiting for a slot at the download client.",
        severity: :info
      },
      %NextStep{description: "Will start when a slot frees up."},
      [:cancel]
    }
  end

  defp derive_acquired_in_queue(%QueueItem{state: :stalled}) do
    {
      %CurrentAction{
        verb: "Stalled",
        description: "Download client can't make progress.",
        severity: :warning
      },
      %NextStep{description: "Change target for a different release, or wait."},
      [:cancel, :change_target, :request_decision]
    }
  end

  defp derive_acquired_in_queue(%QueueItem{state: :paused}) do
    {
      %CurrentAction{
        verb: "Paused",
        description: "Paused at the download client.",
        severity: :info
      },
      %NextStep{description: "Resume it in your download client."},
      [:cancel]
    }
  end

  defp derive_acquired_in_queue(%QueueItem{state: :completed}) do
    {
      %CurrentAction{
        verb: "Verifying",
        description: "Download finished — waiting for the file to be matched.",
        severity: :info
      },
      %NextStep{description: "InboundListener picks it up next."},
      [:cancel]
    }
  end

  defp derive_acquired_in_queue(%QueueItem{state: :error}) do
    {
      %CurrentAction{
        verb: "Error",
        description: "Download client reported an error.",
        severity: :error
      },
      %NextStep{description: "Check your client or change target."},
      [:cancel, :change_target]
    }
  end

  defp derive_acquired_in_queue(%QueueItem{state: :other}) do
    {
      %CurrentAction{
        verb: "Waiting",
        description: "Download client state unrecognized.",
        severity: :info
      },
      %NextStep{description: "Change target to try a different release."},
      [:cancel, :change_target]
    }
  end

  defp download_description(%QueueItem{} = qi) do
    bits =
      []
      |> maybe_prepend(qi.timeleft, &"ETA #{&1}")
      # `qi.progress` is already a 0..100 percentage (see QueueItem) — do
      # not re-scale by 100.
      |> maybe_prepend(qi.progress, &"#{round(&1)}%")
      |> maybe_prepend(qi.download_client, &"From #{&1}")

    case bits do
      [] -> "Downloading."
      parts -> parts |> Enum.reverse() |> Enum.join(" • ")
    end
  end

  defp maybe_prepend(list, nil, _fmt), do: list
  defp maybe_prepend(list, value, fmt), do: [fmt.(value) | list]
end
