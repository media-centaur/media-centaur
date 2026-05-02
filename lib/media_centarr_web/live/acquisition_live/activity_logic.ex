defmodule MediaCentarrWeb.AcquisitionLive.ActivityLogic do
  @moduledoc """
  Pure helpers for the Activity zone of the unified Downloads page —
  extracted per the LiveView logic-extraction policy ([ADR-030]). Tested
  in isolation with `async: true` and struct literals.

  Originally lived under `AutoGrabsLive.Logic` when the activity surface
  was its own page; moved here when manual + auto grabs were unified
  into a single Downloads page (v0.24.0).
  """

  alias MediaCentarr.Acquisition.Grab

  @spec filter_by_search([Grab.t()], String.t()) :: [Grab.t()]
  def filter_by_search(grabs, ""), do: grabs

  def filter_by_search(grabs, search) do
    needle = String.downcase(search)
    Enum.filter(grabs, fn grab -> String.contains?(String.downcase(grab.title), needle) end)
  end

  @spec filter_label(atom()) :: String.t()
  def filter_label(:active), do: "Active"
  def filter_label(:abandoned), do: "Abandoned"
  def filter_label(:cancelled), do: "Cancelled"
  def filter_label(:grabbed), do: "Grabbed"
  def filter_label(:all), do: "All"

  @spec empty_state(atom()) :: String.t()
  def empty_state(:active), do: "No active grabs."
  def empty_state(:abandoned), do: "Nothing has been abandoned."
  def empty_state(:cancelled), do: "Nothing has been cancelled."
  def empty_state(:grabbed), do: "Nothing has been grabbed yet."
  def empty_state(:all), do: "No grabs on record."

  @spec episode_label(Grab.t()) :: String.t()
  def episode_label(%Grab{season_number: nil, episode_number: nil}), do: "—"

  def episode_label(%Grab{season_number: season, episode_number: nil}), do: "Season #{season}"

  def episode_label(%Grab{season_number: season, episode_number: episode}),
    do: "S#{pad2(season)}E#{pad2(episode)}"

  @spec status_label(Grab.t()) :: String.t()
  def status_label(%Grab{status: "grabbed", quality: quality}) when is_binary(quality),
    do: "Grabbed #{quality}"

  def status_label(%Grab{status: "cancelled", cancelled_reason: reason}) when is_binary(reason),
    do: "Cancelled (#{reason})"

  def status_label(%Grab{status: status}), do: status

  @doc """
  Maps a grab status to a `<.badge>` variant (UIDR-002 / `MediaCentarrWeb.CoreComponents.badge/1`).
  """
  @spec status_variant(String.t()) :: String.t()
  def status_variant("searching"), do: "info"
  def status_variant("snoozed"), do: "warning"
  def status_variant("grabbed"), do: "success"
  def status_variant("abandoned"), do: "error"
  def status_variant("cancelled"), do: "ghost"
  def status_variant(_), do: "ghost"

  @doc """
  Short tag for the row's origin. `"auto"` for system-initiated grabs
  (release-tracker driven), `"manual"` for user-submitted from the
  search form. Surfaces alongside the status badge so users can see at
  a glance "did I ask for this or did the system?"
  """
  @spec origin_label(Grab.t()) :: String.t()
  def origin_label(%Grab{origin: "manual"}), do: "manual"
  def origin_label(%Grab{}), do: "auto"

  @doc """
  Maps a grab's origin to a `<.badge>` variant. Manual grabs get a soft-primary
  emphasis (the user reached for them deliberately); auto grabs get a neutral
  outline ("type" — passive classification).
  """
  @spec origin_variant(Grab.t()) :: String.t()
  def origin_variant(%Grab{origin: "manual"}), do: "soft_primary"
  def origin_variant(%Grab{}), do: "type"

  @spec last_attempt_summary(Grab.t()) :: String.t()
  def last_attempt_summary(%Grab{last_attempt_at: nil}), do: "never"

  def last_attempt_summary(%Grab{last_attempt_at: at, last_attempt_outcome: outcome}) do
    outcome = outcome || "—"
    "#{outcome} • #{relative_time(at)}"
  end

  defp pad2(n) when n < 10, do: "0" <> Integer.to_string(n)
  defp pad2(n), do: Integer.to_string(n)

  defp relative_time(%DateTime{} = at) do
    seconds = DateTime.diff(DateTime.utc_now(), at, :second)

    cond do
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end
end
