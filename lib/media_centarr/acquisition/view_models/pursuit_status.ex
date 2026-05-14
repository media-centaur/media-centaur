defmodule MediaCentarr.Acquisition.ViewModels.PursuitStatus do
  @moduledoc """
  Display contract for the pursuit detail page.

  Built by `MediaCentarr.Acquisition.Pursuits.status_for/1` — joins the
  pursuit row with its current target and any matching download-client
  queue item, then routes through the pure `derive/3` function to
  produce `current_action`, `next_step`, and `available_actions`.
  """

  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.Pursuits.State
  alias MediaCentarr.Acquisition.Target
  alias MediaCentarr.Format

  alias MediaCentarr.Acquisition.ViewModels.{
    CurrentAction,
    DownloadProgress,
    NextStep,
    Recipe
  }

  alias MediaCentarr.Downloads.QueueItem

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
    # Loaded pursuit + target structs are stashed so the queue-tick
    # refresh path (`Pursuits.refresh_status_download/2`) can re-derive
    # the dynamic fields against a fresh queue snapshot without a DB
    # round-trip. Not consumed by the template — purely a memoisation
    # handle for the refresh path.
    :pursuit,
    :target,
    available_actions: []
  ]

  @type action :: :cancel | :change_target | :request_decision
  @type staleness :: :fresh | :stale | :very_stale

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
          staleness: staleness(),
          last_activity_at: DateTime.t() | nil,
          available_actions: [action()],
          pursuit: Pursuit.t() | nil,
          target: Target.t() | nil
        }

  @doc """
  Pure mapping from (pursuit, target, queue_item) to the dynamic display
  fields. No DB, no PubSub.

  The recipe lives on the pursuit and drives whether `ChangeTarget` is
  going to auto-pick or surface results for the user — but from the
  view-model's perspective, both recipes offer `:change_target` as the
  recovery action; the worker handles the divergence.
  """
  @spec derive(Pursuit.t(), Target.t() | nil, QueueItem.t() | nil) ::
          {CurrentAction.t(), NextStep.t() | nil, [action()]}
  def derive(%Pursuit{state: "satisfied"}, _target, _qi) do
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

  def derive(%Pursuit{state: "exhausted"} = p, _target, _qi) do
    {
      %CurrentAction{
        verb: "Gave up",
        description: "Exhausted after #{p.attempt_count} attempts.",
        severity: :error
      },
      %NextStep{description: "Start a new pursuit if you still want this."},
      []
    }
  end

  def derive(%Pursuit{state: "cancelled"}, _target, _qi) do
    {
      %CurrentAction{verb: "Cancelled", description: "Pursuit cancelled.", severity: :info},
      nil,
      []
    }
  end

  # Awaiting-decision takes precedence over the regular state:"active"
  # clauses. The pursuit is still active in lifecycle terms, but the
  # user-visible status is "we're blocked on your pick".
  def derive(%Pursuit{state: "active", awaiting_decision_at: %DateTime{}}, _target, _qi) do
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

  def derive(%Pursuit{state: "active"}, nil, _qi) do
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

  def derive(%Pursuit{state: "active"}, %Target{status: "seeking"} = t, _qi) do
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

  def derive(%Pursuit{state: "active"}, %Target{status: "failed"} = t, _qi) do
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

  def derive(%Pursuit{state: "active"}, %Target{status: "cancelled"}, _qi) do
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

  def derive(%Pursuit{state: "active"}, %Target{status: "acquired"}, %QueueItem{state: qstate} = qi)
      when not is_nil(qstate), do: derive_acquired_in_queue(qi)

  def derive(%Pursuit{state: "active"}, %Target{status: "acquired"}, _qi) do
    {
      %CurrentAction{
        verb: "Waiting",
        description: "Not visible in your download client.",
        severity: :info
      },
      %NextStep{
        description: "Either it completed and is being matched, or it never reached the client."
      },
      [:cancel, :change_target]
    }
  end

  def derive(%Pursuit{state: "active"}, %Target{status: "succeeded"}, _qi) do
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
      |> maybe_prepend(qi.progress, &"#{round(&1 * 100)}%")
      |> maybe_prepend(qi.download_client, &"From #{&1}")

    case bits do
      [] -> "Downloading."
      parts -> parts |> Enum.reverse() |> Enum.join(" • ")
    end
  end

  defp maybe_prepend(list, nil, _fmt), do: list
  defp maybe_prepend(list, value, fmt), do: [fmt.(value) | list]
end
