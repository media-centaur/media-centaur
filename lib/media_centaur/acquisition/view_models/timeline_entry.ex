defmodule MediaCentaur.Acquisition.ViewModels.TimelineEntry do
  @moduledoc """
  Display contract for one event in the pursuit timeline.

  Owns the presentation layer for events: per-kind summary string,
  severity classification, and the optional sub-line detail
  (release-picked indexer/quality, target-changed prior title, etc.).

  Build with `from_event/1` from a persisted `%Event{}` row. Pure
  module — no DB, no I/O.
  """

  alias MediaCentaur.Acquisition.CancelReasons
  alias MediaCentaur.Acquisition.Pursuits.Event

  @enforce_keys [:kind, :occurred_at, :summary, :severity]
  defstruct [:kind, :occurred_at, :summary, :severity, :detail]

  @type severity :: :info | :success | :warning | :error
  @type t :: %__MODULE__{
          kind: String.t(),
          occurred_at: DateTime.t(),
          summary: String.t(),
          severity: severity(),
          detail: String.t() | nil
        }

  @doc "Builds a `TimelineEntry` from a persisted `Event` row."
  @spec from_event(Event.t()) :: t()
  def from_event(%Event{} = event) do
    %__MODULE__{
      kind: event.kind,
      occurred_at: event.occurred_at,
      summary: summary_for(event.kind, event.payload),
      severity: severity_for(event.kind),
      detail: detail_for(event)
    }
  end

  # ─── Summary (headline line) ───

  defp summary_for("pursuit_started", %{"origin" => "auto"}), do: "Started by Auto-grab"
  defp summary_for("pursuit_started", %{"origin" => "manual"}), do: "Started by you"
  defp summary_for("pursuit_started", _), do: "Started"

  defp summary_for("search_started", %{"query" => q}) when is_binary(q) and q != "",
    do: "Searching Prowlarr — #{q}"

  defp summary_for("search_started", _), do: "Searching Prowlarr"

  defp summary_for("release_picked", %{"release_title" => t}) when is_binary(t),
    do: "Release picked — #{t}"

  defp summary_for("release_picked", _), do: "Release picked"

  defp summary_for("release_no_match", %{"query" => q}) when is_binary(q) and q != "",
    do: "No acceptable release found — #{q}"

  defp summary_for("release_no_match", _), do: "No acceptable release found"

  # The download client took the job. Named for the client so the row never
  # reads like the download (the goal) starting.
  defp summary_for("download_started", %{"client" => client}) when is_binary(client),
    do: "Started at #{client_label(client)}"

  defp summary_for("download_started", _), do: "Started at the download client"

  # A download's state or health changed: say what it is doing now, in
  # the user's words (the previous entry already said what it was doing
  # before). The state leads; when the health changed too it is the
  # sub-line (`detail_for/1`).
  defp summary_for("health_changed", payload) when is_map(payload) do
    case health_change(payload) do
      {nil, nil} -> "Download changed"
      {nil, health} -> health
      {state, _health} -> state
    end
  end

  defp summary_for("health_changed", _), do: "Health changed"
  defp summary_for("stall_confirmed", _), do: "Stall confirmed"
  defp summary_for("zero_seeders_confirmed", _), do: "Zero seeders confirmed"

  defp summary_for("auto_cancelled", %{"reason" => r}) when is_binary(r),
    do: "Release abandoned — #{cancel_reason_phrase(r)}"

  defp summary_for("auto_cancelled", _), do: "Release abandoned"
  defp summary_for("fallback_initiated", _), do: "Grabbing your pick"
  defp summary_for("user_decision_requested", _), do: "Waiting for you to pick a release"
  defp summary_for("user_decision_recorded", %{"choice" => c}), do: "You picked — #{c}"
  defp summary_for("user_decision_recorded", _), do: "You picked a release"
  defp summary_for("identity_mismatch", _), do: "File sent to Review — it didn't match"
  defp summary_for("identity_verified", _), do: "File landed and matched"
  defp summary_for("pursuit_satisfied", _), do: "Everything landed"
  defp summary_for("pursuit_exhausted", %{"reason" => r}), do: "Gave up (#{r})"
  defp summary_for("pursuit_exhausted", _), do: "Gave up"
  defp summary_for("pursuit_cancelled", %{"cancelled_by" => "user"}), do: "Cancelled by you"
  defp summary_for("pursuit_cancelled", _), do: "Cancelled"
  defp summary_for("target_changed", _), do: "Switched to another release"
  # Legacy event kind from before "target_changed" replaced the re-search
  # affordance — kept as a display alias so old timeline rows read
  # cleanly without a migration.
  defp summary_for("pursuit_re_searched", _), do: "Searched again"
  defp summary_for(kind, _), do: kind

  # The two `Pursuits.Policy` auto-cancel reasons → user copy. Bound through
  # `CancelReasons` rather than repeated as literals: this module reads the
  # same column those commands write, and the two drifting apart is what let
  # the vocabulary rot unnoticed. A head match needs a compile-time value,
  # hence the attributes. Unknown reasons fall back to underscore-stripping
  # so a future reason — and the historical ones — never render raw.
  @download_failed CancelReasons.download_failed()
  @zero_seeders CancelReasons.zero_seeders()

  defp cancel_reason_phrase(@download_failed), do: "download failed"
  defp cancel_reason_phrase(@zero_seeders), do: "no seeders"
  defp cancel_reason_phrase(reason), do: String.replace(reason, "_", " ")

  # The client slug the event payload carries → the name the queue shows
  # (`Downloads.QueueItem.download_client`).
  defp client_label("sabnzbd"), do: "SABnzbd"
  defp client_label("qbittorrent"), do: "qBittorrent"
  defp client_label(other), do: other

  # The phrases for the axes that changed, `{state, health}`, nil where
  # an axis did not change or its new value is absent.
  defp health_change(payload) do
    {changed_to(payload["from_state"], payload["to_state"], &state_phrase/1),
     changed_to(payload["from_health"], payload["to_health"], &health_phrase/1)}
  end

  defp changed_to(from, to, phrase) do
    case {absent(from), absent(to)} do
      {_from, nil} -> nil
      {same, same} -> nil
      {_from, to} -> phrase.(to)
    end
  end

  # Rows written before the nil-stringification fix carry the literal
  # string "nil" — normalized to absence here so old history reads
  # cleanly without a payload rewrite.
  defp absent("nil"), do: nil
  defp absent(value), do: value

  # Internal vocabulary → user copy: `Downloads.QueueItem` states
  # (`other` is qBittorrent's checking/moving phases) and
  # `Downloads.Health` grades. An unknown value is spelled out, never
  # blank.
  defp state_phrase("downloading"), do: "Downloading"
  defp state_phrase("fetching_nzb"), do: "Fetching the NZB"
  defp state_phrase("queued"), do: "Waiting in the download queue"
  defp state_phrase("stalled"), do: "Download stalled"
  defp state_phrase("paused"), do: "Download paused"
  defp state_phrase("verifying"), do: "Verifying the files"
  defp state_phrase("repairing"), do: "Repairing the files"
  defp state_phrase("extracting"), do: "Unpacking the files"
  defp state_phrase("moving"), do: "Moving the files"
  defp state_phrase("completed"), do: "Download finished"
  defp state_phrase("error"), do: "The download client reported an error"
  defp state_phrase("other"), do: "Checking or moving the files"
  defp state_phrase(state), do: "Download " <> String.replace(state, "_", " ")

  defp health_phrase("healthy"), do: "Downloading at a normal rate"
  defp health_phrase("warming_up"), do: "Download starting"
  defp health_phrase("slow"), do: "Downloading slowly"
  defp health_phrase("soft_stall"), do: "Download nearly stalled"
  defp health_phrase("frozen"), do: "Download stopped making progress"
  defp health_phrase("meta_stuck"), do: "Stuck fetching the torrent's details"
  defp health_phrase("queued_long"), do: "Waiting in the queue for a long time"
  defp health_phrase(health), do: "Download " <> String.replace(health, "_", " ")

  # ─── Severity ───

  defp severity_for(kind) when kind in ~w(stall_confirmed zero_seeders_confirmed auto_cancelled),
    do: :warning

  defp severity_for(kind) when kind in ~w(identity_mismatch pursuit_exhausted), do: :error

  defp severity_for(kind) when kind in ~w(release_picked identity_verified pursuit_satisfied),
    do: :success

  defp severity_for(_), do: :info

  # ─── Detail (sub-line) ───
  #
  # Every event row carries `denormalized_pursuit_title` — a snapshot of
  # pursuit.title at write time. We use it here to give each row enough
  # context to read on its own:
  #
  #   "Started by you"                      + "for: Sample Show S01E{05,06}"
  #   "Searched again"                      + "for: Sample Show S01E{05,06}"
  #   "Waiting for you to pick a release"   + the prompt the user is being asked
  #   "Release picked — X"                  + indexer / quality from the payload
  #
  # `target_changed` carries no sub-line: its payload names the *new*
  # target's id, and the pursuit title the old sub-line printed
  # ("abandoned: <show>") was not the release abandoned.
  #
  # The component truncates the sub-line and exposes the full text on
  # hover, so even long release filenames stay scannable.

  # The health under the state, when both changed (see `summary_for/2`).
  defp detail_for(%Event{kind: "health_changed", payload: payload}) when is_map(payload) do
    case health_change(payload) do
      {state, health} when is_binary(state) -> health
      _single -> nil
    end
  end

  defp detail_for(%Event{kind: "release_picked", payload: %{"indexer" => indexer, "quality" => q}})
       when is_binary(indexer) and is_binary(q), do: "#{indexer} • #{q}"

  defp detail_for(%Event{kind: "release_picked", payload: %{"indexer" => indexer}})
       when is_binary(indexer), do: indexer

  defp detail_for(%Event{kind: "release_picked", payload: %{"quality" => q}}) when is_binary(q), do: q

  # The download client's own failure message ("Repair failed, not
  # enough repair blocks") — the one line that tells the user precisely
  # why this release was abandoned.
  defp detail_for(%Event{kind: "auto_cancelled", payload: %{"detail" => detail}})
       when is_binary(detail) and detail != "", do: detail

  defp detail_for(%Event{kind: "pursuit_started", denormalized_pursuit_title: title})
       when is_binary(title) and title != "", do: "for: #{title}"

  defp detail_for(%Event{kind: "user_decision_requested", payload: %{"prompt" => prompt}})
       when is_binary(prompt) and prompt != "", do: prompt

  defp detail_for(%Event{kind: "pursuit_re_searched", denormalized_pursuit_title: title})
       when is_binary(title) and title != "", do: "for: #{title}"

  defp detail_for(%Event{kind: kind, denormalized_pursuit_title: title})
       when kind in ~w(pursuit_satisfied pursuit_cancelled pursuit_exhausted) and is_binary(title) and
              title != "", do: title

  defp detail_for(_), do: nil
end
