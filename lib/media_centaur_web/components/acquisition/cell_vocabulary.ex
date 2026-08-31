defmodule MediaCentaurWeb.Components.Acquisition.CellVocabulary do
  @moduledoc """
  The one unit-cell vocabulary (UIDR-014): plan board, composite
  pursuit-card segments, and the pursuit modal speak the same visual
  language, so approving a plan reads as the board carrying over into
  the pursuit.

  Semantic states and their treatments:

    * `:searching` — dashed, pulsing outline. Plan-only (a pursuit
      never searches open-endedly — search/pursuit boundary).
    * `:claimed` — primary fill. A release covers this unit: plan
      `assigned`, pursuit `active`/downloading. The continuity state —
      a cell that was `:claimed` on the board stays visually `:claimed`
      on the pursuit card until it lands.
    * `:claimed_fused` — primary fill, no border. The capsule interior
      when one pack covers a run of cells (consolidation made visible).
    * `:landed` — success fill. Pursuit `satisfied`; the plan board
      never shows it (nothing grabs before approval).
    * `:below_preference` — info-tinted hollow. Plan `unfound` with
      lower-quality releases on record (UIDR-029) — the world has this
      unit, just not at the user's quality preference. Plan-only.
    * `:gap` — amber hollow. Plan `unfound`, pursuit
      `exhausted`/`cancelled` — a wanted unit nothing currently covers.
    * `:excluded` — muted strikethrough. User removed it from the plan.

  Both renderers consume these treatments — the mapping must not be
  re-implemented inline (that's how the two surfaces drifted before the
  downloads-debt-retirement campaign pinned them).
  """

  @type state ::
          :searching | :claimed | :claimed_fused | :landed | :below_preference | :gap | :excluded

  @doc "Treatment classes for a full-size board cell (w-9 grid cell)."
  @spec cell_treatment(state()) :: String.t()
  def cell_treatment(:searching),
    do: "border border-dashed border-base-content/25 text-base-content/40 animate-pulse"

  def cell_treatment(:claimed), do: "bg-primary/25 border border-primary/60 text-base-content/80"
  def cell_treatment(:claimed_fused), do: "bg-primary/20 text-base-content/80 rounded"
  def cell_treatment(:landed), do: "bg-success/25 border border-success/60 text-base-content/80"
  def cell_treatment(:below_preference), do: "border border-info/40 text-base-content/60"
  def cell_treatment(:gap), do: "border border-warning/50 text-warning/80"
  def cell_treatment(:excluded), do: "bg-base-content/5 text-base-content/25 line-through"

  @doc """
  Treatment classes for a tiny pursuit-card segment (w-2 square) — same
  hues as the full cells, fill-only because a 8px square has no room
  for border articulation.
  """
  @spec segment_treatment(state()) :: String.t()
  def segment_treatment(:landed), do: "bg-success/80"
  def segment_treatment(:claimed), do: "bg-primary/30"
  def segment_treatment(:below_preference), do: "bg-info/20"
  def segment_treatment(:gap), do: "border border-warning/50"
  def segment_treatment(_other), do: "bg-base-content/10"

  @doc "Maps a plan-board cell state onto the shared vocabulary."
  @spec from_plan_state(:searching | :assigned | :unfound | :excluded, boolean()) :: state()
  def from_plan_state(:assigned, true = _in_capsule), do: :claimed_fused
  def from_plan_state(:assigned, _in_capsule), do: :claimed
  def from_plan_state(:searching, _in_capsule), do: :searching
  def from_plan_state(:below_preference, _in_capsule), do: :below_preference
  def from_plan_state(:unfound, _in_capsule), do: :gap
  def from_plan_state(:excluded, _in_capsule), do: :excluded

  @doc "Maps a pursuit unit state string onto the shared vocabulary."
  @spec from_unit_state(String.t()) :: state()
  def from_unit_state("satisfied"), do: :landed
  def from_unit_state("active"), do: :claimed
  def from_unit_state("exhausted"), do: :gap
  def from_unit_state("cancelled"), do: :gap
  def from_unit_state(_other), do: :gap
end
