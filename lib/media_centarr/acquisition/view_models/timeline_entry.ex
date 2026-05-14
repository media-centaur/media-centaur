defmodule MediaCentarr.Acquisition.ViewModels.TimelineEntry do
  @moduledoc """
  Display contract for one event in the pursuit timeline.

  Owns the presentation layer for events: per-kind summary string,
  severity classification, and the optional sub-line detail
  (release-picked indexer/quality, target-changed prior title, etc.).

  Build with `from_event/1` from a persisted `%Event{}` row. Pure
  module — no DB, no I/O.
  """

  alias MediaCentarr.Acquisition.Pursuits.Event

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

  defp summary_for("pursuit_started", %{"origin" => "auto"}), do: "Pursuit started (auto)"
  defp summary_for("pursuit_started", %{"origin" => "manual"}), do: "Pursuit started (manual)"
  defp summary_for("pursuit_started", _), do: "Pursuit started"

  defp summary_for("search_started", %{"query" => q}) when is_binary(q) and q != "",
    do: "Searching Prowlarr — #{q}"

  defp summary_for("search_started", _), do: "Searching Prowlarr"

  defp summary_for("release_picked", %{"release_title" => t}) when is_binary(t),
    do: "Release picked — #{t}"

  defp summary_for("release_picked", _), do: "Release picked"

  defp summary_for("release_no_match", %{"query" => q}) when is_binary(q) and q != "",
    do: "No acceptable release found — #{q}"

  defp summary_for("release_no_match", _), do: "No acceptable release found"
  defp summary_for("download_started", _), do: "Download started"

  defp summary_for("health_changed", payload) when is_map(payload) do
    state_part = transition_phrase(payload["from_state"], payload["to_state"])
    health_part = transition_phrase(payload["from_health"], payload["to_health"])

    case {state_part, health_part} do
      {nil, nil} -> "Health changed"
      {state, nil} -> "State #{state}"
      {nil, health} -> "Health #{health}"
      {state, health} -> "State #{state}, health #{health}"
    end
  end

  defp summary_for("health_changed", _), do: "Health changed"
  defp summary_for("stall_confirmed", _), do: "Stall confirmed"
  defp summary_for("zero_seeders_confirmed", _), do: "Zero seeders confirmed"
  defp summary_for("auto_cancelled", %{"reason" => r}), do: "Auto-cancelled (#{r})"
  defp summary_for("auto_cancelled", _), do: "Auto-cancelled"
  defp summary_for("fallback_initiated", _), do: "Fallback initiated"
  defp summary_for("user_decision_requested", _), do: "User decision requested"
  defp summary_for("user_decision_recorded", %{"choice" => c}), do: "User picked — #{c}"
  defp summary_for("user_decision_recorded", _), do: "User decision recorded"
  defp summary_for("identity_mismatch", _), do: "Identity mismatch — file routed to Review"
  defp summary_for("identity_verified", _), do: "Identity verified"
  defp summary_for("pursuit_satisfied", _), do: "Pursuit satisfied"
  defp summary_for("pursuit_exhausted", %{"reason" => r}), do: "Pursuit exhausted (#{r})"
  defp summary_for("pursuit_exhausted", _), do: "Pursuit exhausted"
  defp summary_for("pursuit_cancelled", _), do: "Pursuit cancelled"
  defp summary_for("target_changed", _), do: "Target changed"
  # Legacy event kind from before "target_changed" replaced the re-search
  # affordance — kept as a display alias so old timeline rows read
  # cleanly without a migration.
  defp summary_for("pursuit_re_searched", _), do: "Re-searched Prowlarr"
  defp summary_for(kind, _), do: kind

  defp transition_phrase(same, same), do: nil
  defp transition_phrase(nil, to) when is_binary(to), do: to
  defp transition_phrase(from, to) when is_binary(from) and is_binary(to), do: "#{from} → #{to}"
  defp transition_phrase(_, _), do: nil

  # ─── Severity ───

  defp severity_for(kind) when kind in ~w(stall_confirmed zero_seeders_confirmed), do: :warning
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
  #   "Pursuit started (manual)"        + "for: Rick and Morty the Anime S01E{05,06}"
  #   "Target changed"                  + "abandoned: Rick-and-Morty-The-Anime-S01E05-Family.1080p…"
  #   "Re-searched Prowlarr"            + "for: Rick and Morty the Anime S01E{05,06}"
  #   "User decision requested"         + the prompt the user is being asked
  #   "Release picked — X"              + indexer / quality from the payload
  #
  # The component truncates the sub-line and exposes the full text on
  # hover, so even long release filenames stay scannable.

  defp detail_for(%Event{kind: "release_picked", payload: %{"indexer" => indexer, "quality" => q}})
       when is_binary(indexer) and is_binary(q), do: "#{indexer} • #{q}"

  defp detail_for(%Event{kind: "release_picked", payload: %{"indexer" => indexer}})
       when is_binary(indexer), do: indexer

  defp detail_for(%Event{kind: "release_picked", payload: %{"quality" => q}}) when is_binary(q), do: q

  defp detail_for(%Event{kind: "pursuit_started", denormalized_pursuit_title: title})
       when is_binary(title) and title != "", do: "for: #{title}"

  defp detail_for(%Event{kind: "user_decision_requested", payload: %{"prompt" => prompt}})
       when is_binary(prompt) and prompt != "", do: prompt

  defp detail_for(%Event{kind: "target_changed", denormalized_pursuit_title: title})
       when is_binary(title) and title != "", do: "abandoned: #{title}"

  defp detail_for(%Event{kind: "pursuit_re_searched", denormalized_pursuit_title: title})
       when is_binary(title) and title != "", do: "for: #{title}"

  defp detail_for(%Event{kind: kind, denormalized_pursuit_title: title})
       when kind in ~w(pursuit_satisfied pursuit_cancelled pursuit_exhausted) and is_binary(title) and
              title != "", do: title

  defp detail_for(_), do: nil
end
