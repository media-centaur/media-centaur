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
  alias MediaCentarr.Format

  @filter_atoms [:active, :abandoned, :cancelled, :grabbed, :all]

  @spec filter_by_search([Grab.t()], String.t()) :: [Grab.t()]
  def filter_by_search(grabs, ""), do: grabs

  def filter_by_search(grabs, search) do
    needle = String.downcase(search)
    Enum.filter(grabs, fn grab -> String.contains?(String.downcase(grab.title), needle) end)
  end

  @doc """
  Parses a `?filter=` URL value or a `phx-value-filter` event value into the
  filter atom. Unknown values fall back to `:active` — the page's default.
  """
  @spec parse_filter(String.t() | nil) ::
          :active | :abandoned | :cancelled | :grabbed | :all
  def parse_filter("active"), do: :active
  def parse_filter("abandoned"), do: :abandoned
  def parse_filter("cancelled"), do: :cancelled
  def parse_filter("grabbed"), do: :grabbed
  def parse_filter("all"), do: :all
  def parse_filter(_), do: :active

  @doc "Every filter atom in the order the chips render."
  @spec filter_atoms() :: [atom()]
  def filter_atoms, do: @filter_atoms

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

  def episode_label(%Grab{season_number: season, episode_number: episode}),
    do: Format.episode_label(season, episode)

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
    "#{outcome} • #{Format.relative_ago(at)}"
  end
end
