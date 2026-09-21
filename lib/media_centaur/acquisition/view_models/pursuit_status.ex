defmodule MediaCentaur.Acquisition.ViewModels.PursuitStatus do
  @moduledoc """
  Display contract for the pursuit detail page.

  Built by `MediaCentaur.Acquisition.Pursuits.status_from/2` — joins the
  pursuit row with its unit, the unit's current target, and any
  matching download-client queue item, then routes through the pure
  `derive/6` function to produce `current_action`, `next_step`, and
  `available_actions`. The unit carries the attempt thread (ADR-055);
  the modal shows the sole unit's thread until the multi-unit
  drill-down lands.

  `derive/6` owns *copy*, not lifecycle logic: `Pursuits.Stage` decides where
  the download has got to and this module says it in words. Adding a status
  line means adding a stage there, not another clause here.
  """

  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Recipe, Stage, StatusContext, Unit}
  alias MediaCentaur.Acquisition.Pursuits.State
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Format

  alias MediaCentaur.Acquisition.ViewModels.{
    CurrentAction,
    DownloadProgress,
    NextStep
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
    # Loaded pursuit + unit + target structs, and the page-level
    # `StatusContext`, are stashed so the queue-tick refresh path
    # (`Pursuits.refresh_status_download/2`) can re-derive the dynamic fields
    # against a fresh queue snapshot without a DB round-trip. Not consumed by
    # the template — purely a memoisation handle for the refresh path.
    :pursuit,
    :unit,
    :target,
    :context,
    available_actions: [],
    downloads: [],
    downloads_done: 0,
    search_queries: []
  ]

  @type action :: :cancel | :change_target | :request_decision
  @type staleness :: :fresh | :stale | :very_stale

  @type t :: %__MODULE__{
          pursuit_id: Ecto.UUID.t(),
          title: String.t(),
          state: State.t(),
          origin: :auto | :manual,
          recipe: Recipe.t(),
          search_queries: [String.t()],
          criteria_summary: String.t() | nil,
          current_action: CurrentAction.t(),
          next_step: NextStep.t() | nil,
          download: DownloadProgress.t() | nil,
          downloads: [%{download: DownloadProgress.t(), release_title: String.t() | nil}],
          downloads_done: non_neg_integer(),
          staleness: staleness(),
          last_activity_at: DateTime.t() | nil,
          available_actions: [action()],
          pursuit: Pursuit.t() | nil,
          unit: Unit.t() | nil,
          target: Target.t() | nil,
          context: StatusContext.t() | nil
        }

  @doc """
  Pure mapping from a pursuit and its download position to the dynamic display
  fields. No DB, no PubSub, no Settings — every system-level fact arrives on
  the `StatusContext`.

  Precedence, highest first:

  1. The pursuit's own terminal outcome (satisfied / partial / exhausted /
     cancelled) — nothing about the download matters once it is over.
  2. A pending user decision. The unit is still active in lifecycle terms, but
     the user-visible status is "we're blocked on your pick", and that outranks
     an integration hold: the pick is the user's to make either way.
  3. A global hold on a down Prowlarr, which only bites before the search.
  4. A grab that reached Prowlarr but not the download client behind it — an
     outage, not a bad release.
  5. `Stage.of/4`, mapped to copy.

  The unit carries the attempt thread (decision flag, attempt count — ADR-055);
  the target carries the per-release facts. The recipe lives on the pursuit and
  drives whether `ChangeTarget` auto-picks or surfaces results, but from here
  both recipes offer `:change_target` as the recovery action; the worker handles
  the divergence.
  """
  @spec derive(
          Pursuit.t(),
          Unit.t() | nil,
          Target.t() | nil,
          QueueItem.t() | nil,
          Stage.location(),
          StatusContext.t()
        ) :: {CurrentAction.t(), NextStep.t() | nil, [action()]}
  def derive(pursuit, unit, target, queue_item, location, context)

  def derive(%Pursuit{state: "satisfied"}, _unit, _target, _qi, _location, _context) do
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

  def derive(%Pursuit{state: "partial"}, _unit, _target, _qi, _location, _context) do
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

  def derive(%Pursuit{state: "exhausted"}, unit, _target, _qi, _location, _context) do
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

  def derive(%Pursuit{state: "cancelled"}, _unit, _target, _qi, _location, _context) do
    {
      %CurrentAction{verb: "Cancelled", description: "Pursuit cancelled.", severity: :info},
      nil,
      []
    }
  end

  def derive(%Pursuit{state: "active"}, unit, target, queue_item, location, %StatusContext{} = context) do
    stage = Stage.of(target, queue_item, location, context)

    cond do
      awaiting_decision?(unit) -> decision_action()
      held_before_the_search?(stage, context) -> held_action(context.held_integration)
      handoff_outage?(stage, target) -> outage_action(target)
      stage == :at_client -> at_client_action(queue_item)
      true -> stage_action(stage, target, unit)
    end
  end

  defp awaiting_decision?(%Unit{awaiting_decision_at: %DateTime{}}), do: true
  defp awaiting_decision?(_unit), do: false

  # The hold is global and only bites before the work starts: once a release is
  # grabbed, Prowlarr being down changes nothing about the download in flight.
  defp held_before_the_search?(:seeking, %StatusContext{held_integration: integration}),
    do: not is_nil(integration)

  defp held_before_the_search?(_stage, _context), do: false

  # The last grab reached Prowlarr but not the download client behind it — an
  # outage, not a bad release. The worker snoozed briefly without charging an
  # attempt; say so, or the user reaches for an alternative release that cannot
  # help.
  defp handoff_outage?(:seeking, %Target{last_attempt_outcome: "download_client_unavailable"}), do: true

  defp handoff_outage?(_stage, _target), do: false

  defp decision_action do
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

  # Held before the search: no clock, because it resumes on recovery rather
  # than on a timer, and no decision to request — that would need the same
  # integration.
  defp held_action(integration) do
    {
      %CurrentAction{
        verb: "Waiting",
        description: held_description(integration),
        severity: :warning
      },
      nil,
      [:cancel]
    }
  end

  defp outage_action(%Target{} = target) do
    {
      %CurrentAction{
        verb: "Waiting",
        description: outage_description(target),
        severity: :warning
      },
      %NextStep{
        description: "Check that the download client is running. The same release will be retried."
      },
      [:cancel, :request_decision]
    }
  end

  defp stage_action(:no_target, _target, _unit) do
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

  defp stage_action(:seeking, %Target{} = target, _unit) do
    {
      %CurrentAction{
        verb: "Searching",
        description: searching_description(target),
        severity: :info
      },
      %NextStep{description: "Trying expanded queries — will pick the best match or snooze."},
      [:cancel, :request_decision]
    }
  end

  # Grabbed, and the download client has not shown it to us yet. Prowlarr
  # accepting a grab is a hand-off, not a download: without this stage the row
  # read "Downloaded — Finished downloading" for the seconds between the grab
  # and the client registering the release.
  defp stage_action(:handed_off, _target, _unit) do
    {
      %CurrentAction{
        verb: "Grabbed",
        description: "Waiting for your download client to pick it up.",
        severity: :info
      },
      %NextStep{description: "It'll say so here if your client never takes it."},
      [:cancel]
    }
  end

  defp stage_action(:missing, _target, _unit) do
    {
      %CurrentAction{
        verb: "Not at your client",
        description: "Prowlarr accepted the grab but the download never started.",
        severity: :warning
      },
      %NextStep{description: "Change target to try a different release."},
      [:cancel, :change_target]
    }
  end

  defp stage_action(:in_review, _target, _unit) do
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

  defp stage_action(:left_client, _target, _unit) do
    {
      %CurrentAction{
        verb: "Downloaded",
        description: "Finished at your download client. Importing, or already in your library.",
        severity: :info
      },
      %NextStep{
        description:
          "It may still be importing or already be in your library; change target to grab a different release."
      },
      [:cancel, :change_target]
    }
  end

  defp stage_action(:done, _target, _unit) do
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

  defp stage_action(:failed, %Target{} = target, _unit) do
    {
      %CurrentAction{
        verb: "Stopped",
        description: "Auto-search gave up after #{target.attempt_count} attempts.",
        severity: :warning
      },
      %NextStep{description: "Change target or pick a release manually."},
      [:cancel, :change_target, :request_decision]
    }
  end

  defp stage_action(:cancelled, _target, _unit) do
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

  # No attempt number: an outage does not charge one, so counting would
  # contradict the row.
  defp outage_description(%Target{next_attempt_at: nil}),
    do: "Prowlarr could not reach your download client."

  defp outage_description(%Target{next_attempt_at: %DateTime{} = at}),
    do: "Prowlarr could not reach your download client. Next attempt #{Format.relative_in(at)}."

  # Held on a down Prowlarr: no attempt number and no countdown, because
  # nothing was spent and the work resumes on recovery rather than on a
  # timer. Same verb and severity as the outage copy — to the user it is
  # the same wait.
  defp held_description(:prowlarr), do: "Prowlarr is unreachable. Resumes when it answers again."

  defp at_client_action(%QueueItem{state: :downloading} = qi) do
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

  defp at_client_action(%QueueItem{state: :queued}) do
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

  defp at_client_action(%QueueItem{state: :stalled}) do
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

  defp at_client_action(%QueueItem{state: :paused}) do
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

  # SABnzbd's post-download pipeline: verify → repair → unpack → move.
  # All healthy, all hands-off — offering change_target here invites
  # abandoning a download that is seconds-to-minutes from landing.
  defp at_client_action(%QueueItem{state: state})
       when state in [:verifying, :repairing, :extracting, :moving] do
    {
      %CurrentAction{
        verb: postprocessing_verb(state),
        description: "Post-processing at the download client.",
        severity: :info
      },
      %NextStep{description: "The finished file lands in the library when this completes."},
      [:cancel]
    }
  end

  defp at_client_action(%QueueItem{state: :completed}) do
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

  # A failure detail means the client declared the download
  # unrecoverable (SABnzbd's "Repair failed, not enough repair blocks" /
  # "Unpacking failed") — show the client's own words, and set the
  # expectation that the Watcher pivots to a different release on its
  # own. Without a detail (qBittorrent's ambiguous error states) the
  # recovery is manual.
  defp at_client_action(%QueueItem{state: :error, failure_message: message} = qi)
       when is_binary(message) do
    {
      %CurrentAction{
        verb: "Failed",
        description: "#{qi.download_client || "Download client"}: #{message}",
        severity: :error
      },
      %NextStep{
        description:
          "A different release will be tried automatically — open #{qi.download_client || "your download client"} for the job log."
      },
      [:cancel, :change_target]
    }
  end

  defp at_client_action(%QueueItem{state: :error}) do
    {
      %CurrentAction{
        verb: "Failed",
        description: "Download client reported an error.",
        severity: :error
      },
      %NextStep{description: "Check your download client or change target."},
      [:cancel, :change_target]
    }
  end

  defp at_client_action(%QueueItem{}) do
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

  @doc """
  Composite-download presentation (UIDR-029 follow-up): finished entries
  (progress at 100%) leave the per-file list — the header carries their
  count — and a multi-file "Downloading" header aggregates ("N of M
  finished • From <client>") instead of narrating one file's telemetry.
  Single-download pursuits keep their per-file description; non-download
  verbs are never rewritten. Returns `{action, active_entries, done}`.
  """
  @spec compose_downloads(CurrentAction.t(), [map()]) ::
          {CurrentAction.t(), [map()], non_neg_integer()}
  def compose_downloads(%CurrentAction{} = action, downloads) when is_list(downloads) do
    {done, active} = Enum.split_with(downloads, &finished_entry?/1)
    total = length(downloads)

    action =
      if action.verb == "Downloading" and total > 1 do
        %{action | description: composite_description(length(done), total, downloads)}
      else
        action
      end

    {action, active, length(done)}
  end

  defp finished_entry?(%{download: download}), do: DownloadProgress.finished?(download)
  defp finished_entry?(_entry), do: false

  defp composite_description(done, total, downloads) do
    base = "#{done} of #{total} finished"

    case Enum.find_value(downloads, fn %{download: %DownloadProgress{client: client}} -> client end) do
      nil -> base
      client -> base <> " • From " <> client
    end
  end

  @doc """
  The pursuit's quality-bound snapshot in user copy — never raw
  `key: value` dumps for the known bounds ("floor" and storage labels
  are internal vocabulary). Unknown keys fall back to `key: value`
  rather than disappearing.
  """
  @spec criteria_summary(map() | nil) :: String.t() | nil
  def criteria_summary(nil), do: nil
  def criteria_summary(map) when map_size(map) == 0, do: nil

  def criteria_summary(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> criterion_order(key) end)
    |> Enum.map_join(", ", &describe_criterion/1)
  end

  defp criterion_order("min_quality"), do: 0
  defp criterion_order("max_quality"), do: 1
  defp criterion_order(_other), do: 2

  defp describe_criterion({"min_quality", "any"}), do: "lower quality accepted"
  defp describe_criterion({"min_quality", "hd_1080p"}), do: "1080p or better"
  defp describe_criterion({"min_quality", "uhd_4k"}), do: "4K only"
  defp describe_criterion({"max_quality", "hd_1080p"}), do: "up to 1080p"
  defp describe_criterion({"max_quality", "uhd_4k"}), do: "up to 4K"
  defp describe_criterion({key, value}), do: "#{key}: #{value}"

  defp postprocessing_verb(:verifying), do: "Verifying"
  defp postprocessing_verb(:repairing), do: "Repairing"
  defp postprocessing_verb(:extracting), do: "Unpacking"
  defp postprocessing_verb(:moving), do: "Moving"

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
