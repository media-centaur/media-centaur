defmodule MediaCentarr.Acquisition.ViewModels.PursuitStatus do
  @moduledoc """
  Display contract for the pursuit detail page.

  Built by `MediaCentarr.Acquisition.Pursuits.status_for/1` — joins the
  pursuit row with its latest grab and any matching download-client queue
  item, then routes through the pure `derive/3` function to produce
  `current_action`, `next_step`, and `available_actions`.
  """

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.Pursuits.State

  alias MediaCentarr.Acquisition.ViewModels.{
    CurrentAction,
    DownloadProgress,
    NextStep,
    Target
  }

  alias MediaCentarr.Downloads.QueueItem

  @enforce_keys [
    :pursuit_id,
    :title,
    :state,
    :origin,
    :target,
    :current_action,
    :available_actions,
    :staleness
  ]
  defstruct [
    :pursuit_id,
    :title,
    :state,
    :origin,
    :target,
    :criteria_summary,
    :current_action,
    :next_step,
    :download,
    :staleness,
    :last_activity_at,
    available_actions: []
  ]

  @type action :: :cancel | :re_search | :request_decision
  @type staleness :: :fresh | :stale | :very_stale

  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          title: String.t(),
          state: State.t(),
          origin: :auto | :manual,
          target: Target.t(),
          criteria_summary: String.t() | nil,
          current_action: CurrentAction.t(),
          next_step: NextStep.t() | nil,
          download: DownloadProgress.t() | nil,
          staleness: staleness(),
          last_activity_at: DateTime.t() | nil,
          available_actions: [action()]
        }

  @doc """
  Pure mapping from (pursuit, grab, queue_item) to the dynamic display fields.
  No DB, no PubSub. See the spec's truth table.

  Manual-origin pursuits cannot be auto-re-searched (the SearchAndGrab
  worker depends on TMDB metadata they don't have); their actions list
  has `:re_search` replaced with `:request_decision` so the UI offers
  the decision-card recovery path instead of a button that would fail.
  """
  @spec derive(Pursuit.t(), Grab.t() | nil, QueueItem.t() | nil) ::
          {CurrentAction.t(), NextStep.t() | nil, [action()]}
  def derive(%Pursuit{} = pursuit, grab, queue_item) do
    {current_action, next_step, actions} = derive_raw(pursuit, grab, queue_item)
    {current_action, next_step, adjust_actions_for_origin(pursuit, actions)}
  end

  defp adjust_actions_for_origin(%Pursuit{origin: "manual"}, actions) do
    if :re_search in actions do
      actions
      |> Enum.reject(&(&1 == :re_search))
      |> Kernel.++([:request_decision])
      |> Enum.uniq()
    else
      actions
    end
  end

  defp adjust_actions_for_origin(_pursuit, actions), do: actions

  defp derive_raw(%Pursuit{state: "satisfied"}, _grab, _qi) do
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

  defp derive_raw(%Pursuit{state: "exhausted"} = p, _grab, _qi) do
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

  defp derive_raw(%Pursuit{state: "cancelled"}, _grab, _qi) do
    {
      %CurrentAction{verb: "Cancelled", description: "Pursuit cancelled.", severity: :info},
      nil,
      []
    }
  end

  defp derive_raw(%Pursuit{state: "needs_decision"}, _grab, _qi) do
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

  defp derive_raw(%Pursuit{state: "active"}, nil, _qi) do
    {
      %CurrentAction{
        verb: "Unknown",
        description: "Pursuit has no linked grab — please cancel.",
        severity: :warning
      },
      nil,
      [:cancel]
    }
  end

  defp derive_raw(%Pursuit{state: "active"}, %Grab{status: "searching"} = g, _qi) do
    {
      %CurrentAction{
        verb: "Searching",
        description: "Looking for an acceptable release (attempt #{g.attempt_count + 1}).",
        severity: :info
      },
      %NextStep{description: "Trying expanded queries — will pick the best match or snooze."},
      [:cancel]
    }
  end

  defp derive_raw(%Pursuit{state: "active"}, %Grab{status: "snoozed"}, _qi) do
    {
      %CurrentAction{
        verb: "Snoozed",
        description: "Waiting before the next search attempt.",
        severity: :info
      },
      %NextStep{description: "Will resume automatically."},
      [:cancel, :re_search, :request_decision]
    }
  end

  defp derive_raw(%Pursuit{state: "active"}, %Grab{status: "abandoned"} = g, _qi) do
    {
      %CurrentAction{
        verb: "Stopped",
        description: "Auto-search gave up after #{g.attempt_count} attempts.",
        severity: :warning
      },
      %NextStep{description: "Re-search or pick a release manually."},
      [:cancel, :re_search, :request_decision]
    }
  end

  defp derive_raw(%Pursuit{state: "active"}, %Grab{status: "cancelled"}, _qi) do
    {
      %CurrentAction{
        verb: "Stopped",
        description: "Underlying grab was cancelled.",
        severity: :warning
      },
      %NextStep{description: "Re-search to restart."},
      [:cancel, :re_search]
    }
  end

  defp derive_raw(%Pursuit{state: "active"}, %Grab{status: "grabbed"}, %QueueItem{state: qstate} = qi)
       when not is_nil(qstate), do: derive_grabbed_in_queue(qi)

  defp derive_raw(%Pursuit{state: "active"}, %Grab{status: "grabbed"}, _qi) do
    {
      %CurrentAction{
        verb: "Waiting",
        description: "Not visible in your download client.",
        severity: :info
      },
      %NextStep{
        description: "Either it completed and is being matched, or it never reached the client."
      },
      [:cancel, :re_search]
    }
  end

  defp derive_grabbed_in_queue(%QueueItem{state: :downloading} = qi) do
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

  defp derive_grabbed_in_queue(%QueueItem{state: :queued}) do
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

  defp derive_grabbed_in_queue(%QueueItem{state: :stalled}) do
    {
      %CurrentAction{
        verb: "Stalled",
        description: "Download client can't make progress.",
        severity: :warning
      },
      %NextStep{description: "Re-search for a different release, or wait."},
      [:cancel, :re_search, :request_decision]
    }
  end

  defp derive_grabbed_in_queue(%QueueItem{state: :paused}) do
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

  defp derive_grabbed_in_queue(%QueueItem{state: :completed}) do
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

  defp derive_grabbed_in_queue(%QueueItem{state: :error}) do
    {
      %CurrentAction{
        verb: "Error",
        description: "Download client reported an error.",
        severity: :error
      },
      %NextStep{description: "Check your client or re-search for a different release."},
      [:cancel, :re_search]
    }
  end

  defp derive_grabbed_in_queue(%QueueItem{state: :other}) do
    {
      %CurrentAction{
        verb: "Waiting",
        description: "Download client state unrecognized.",
        severity: :info
      },
      %NextStep{description: "Re-search to try a different release."},
      [:cancel, :re_search]
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
