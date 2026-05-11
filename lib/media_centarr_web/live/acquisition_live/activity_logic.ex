defmodule MediaCentarrWeb.AcquisitionLive.ActivityLogic do
  @moduledoc """
  Pure helpers for the Activity zone of the unified Downloads page —
  extracted per the LiveView logic-extraction policy ([ADR-030]).
  Tested in isolation with `async: true` and struct literals.

  Operates on `Target` rows (renamed from `Grab` in the
  pursuit/target/recipe refactor). The activity zone displays per-target
  history; the recipe and TMDB metadata live on the pursuit and aren't
  surfaced here.
  """

  alias MediaCentarr.Acquisition.Target
  alias MediaCentarr.Format

  @filter_atoms [:active, :failed, :cancelled, :acquired, :succeeded, :all]

  @spec filter_by_search([Target.t()], String.t()) :: [Target.t()]
  def filter_by_search(targets, ""), do: targets

  def filter_by_search(targets, search) do
    needle = String.downcase(search)

    Enum.filter(targets, fn target ->
      String.contains?(String.downcase(target.title || ""), needle)
    end)
  end

  @doc """
  Parses a `?filter=` URL value or a `phx-value-filter` event value
  into the filter atom. Unknown values fall back to `:active`.
  """
  @spec parse_filter(String.t() | nil) ::
          :active | :failed | :cancelled | :acquired | :succeeded | :all
  def parse_filter("active"), do: :active
  def parse_filter("failed"), do: :failed
  def parse_filter("cancelled"), do: :cancelled
  def parse_filter("acquired"), do: :acquired
  def parse_filter("succeeded"), do: :succeeded
  def parse_filter("all"), do: :all
  def parse_filter(_), do: :active

  @doc "Every filter atom in the order the chips render."
  @spec filter_atoms() :: [atom()]
  def filter_atoms, do: @filter_atoms

  @spec filter_label(atom()) :: String.t()
  def filter_label(:active), do: "Active"
  def filter_label(:failed), do: "Failed"
  def filter_label(:cancelled), do: "Cancelled"
  def filter_label(:acquired), do: "Acquired"
  def filter_label(:succeeded), do: "Succeeded"
  def filter_label(:all), do: "All"

  @spec empty_state(atom()) :: String.t()
  def empty_state(:active), do: "No active targets."
  def empty_state(:failed), do: "Nothing has failed."
  def empty_state(:cancelled), do: "Nothing has been cancelled."
  def empty_state(:acquired), do: "Nothing acquired yet."
  def empty_state(:succeeded), do: "Nothing succeeded yet."
  def empty_state(:all), do: "No targets on record."

  @spec status_label(Target.t()) :: String.t()
  def status_label(%Target{status: "acquired", quality: quality}) when is_binary(quality),
    do: "Acquired #{quality}"

  def status_label(%Target{status: "cancelled", cancelled_reason: reason}) when is_binary(reason),
    do: "Cancelled (#{reason})"

  def status_label(%Target{status: "failed", cancelled_reason: reason}) when is_binary(reason),
    do: "Failed (#{reason})"

  def status_label(%Target{status: status}), do: status

  @doc """
  Maps a target status to a `<.badge>` variant (UIDR-002 /
  `MediaCentarrWeb.CoreComponents.badge/1`).
  """
  @spec status_variant(String.t()) :: String.t()
  def status_variant("seeking"), do: "info"
  def status_variant("acquired"), do: "success"
  def status_variant("succeeded"), do: "success"
  def status_variant("failed"), do: "error"
  def status_variant("cancelled"), do: "ghost"
  def status_variant(_), do: "ghost"

  @doc """
  Short tag for the row's origin. `"auto"` for system-initiated targets
  (release-tracker driven), `"manual"` for user-picked from the search
  form or decision card.
  """
  @spec origin_label(Target.t()) :: String.t()
  def origin_label(%Target{origin: "manual"}), do: "manual"
  def origin_label(%Target{}), do: "auto"

  @doc """
  Maps a target's origin to a `<.badge>` variant. Manual gets a
  soft-primary emphasis; auto gets a neutral outline.
  """
  @spec origin_variant(Target.t()) :: String.t()
  def origin_variant(%Target{origin: "manual"}), do: "soft_primary"
  def origin_variant(%Target{}), do: "type"

  @spec last_attempt_summary(Target.t()) :: String.t()
  def last_attempt_summary(%Target{last_attempt_at: nil}), do: "never"

  def last_attempt_summary(%Target{last_attempt_at: at, last_attempt_outcome: outcome}) do
    outcome = outcome || "—"
    "#{outcome} • #{Format.relative_ago(at)}"
  end
end
