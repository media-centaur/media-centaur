defmodule MediaCentaurWeb.Storybook.ReleaseTracking.TrackingModeControl do
  @moduledoc """
  The tracking-mode control (ADR-065, UIDR-035): Off · Watch · Ask · Grab ·
  Default, the same control on every title surface: the heading, the
  selected mode's consequence, the notes and the quality acceptance row.
  """

  use PhoenixStorybook.Story, :component

  def function,
    do: &MediaCentaurWeb.Components.ReleaseTracking.TrackingModeControl.tracking_mode_control/1

  def render_source, do: :function

  def template do
    """
    <div class="max-w-xl p-4">
      <.psb-variation/>
    </div>
    """
  end

  defp base(overrides) do
    Map.merge(
      %{
        id: "tracking-mode-story",
        ref: "tv_series-42",
        default_grab_mode: "ask",
        acquisition?: true,
        on_watchlist?: true
      },
      overrides
    )
  end

  def variations do
    [
      %VariationGroup{
        id: :modes,
        description: "Every mode, pressed, with its one-line consequence beneath.",
        variations:
          for mode <- [:none, :watch, :ask, :grab, :global] do
            %Variation{id: mode, attributes: base(%{mode: mode})}
          end
      },
      %Variation{
        id: :untracked,
        description:
          "A title never tracked and not yet on the watchlist (nil mode reads as Off): " <>
            "the copy states that choosing a mode adds it to the watchlist.",
        attributes: base(%{mode: nil, on_watchlist?: false})
      },
      %Variation{
        id: :default_off,
        description: "Default with the global setting off: Default resolves to Watch, and says so.",
        attributes: base(%{mode: :global, default_grab_mode: "off"})
      },
      %Variation{
        id: :acquisition_not_ready,
        description:
          "No indexer or download client yet: the grab modes stay selectable, and the " <>
            "note says nothing downloads until acquisition is set up.",
        attributes: base(%{mode: :global, default_grab_mode: "all_releases", acquisition?: false})
      },
      %Variation{
        id: :lower_quality_accepted,
        description:
          "The title carries the per-title acceptance set from a plan board (ADR-063 §2): " <>
            "the acceptance row with Reset follows the control.",
        attributes: base(%{mode: :grab, lower_quality_accepted?: true})
      }
    ]
  end
end
