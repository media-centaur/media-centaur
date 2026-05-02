defmodule MediaCentarrWeb.Storybook.Detail.PlayCard do
  @moduledoc """
  Playback action row in the entity detail panel — Play/Resume button,
  thin progress bar with optional "remaining" text, and a "More info"
  toggle.

  The component is pure presentation: callers pre-compute `label`,
  `percent`, `remaining_text`, and `available` (typically via
  `Detail.Logic.playback_props/3`) and pass them in. No context lookups
  happen at render time, which is why the variations below can be flat
  literal data with no fakes or stubs.

  Visual contract pinned by the variations:

    * The progress bar only renders when `percent > 0` (`:ready_to_play`
      proves the absence; `:in_progress_low/mid/high` exercise widths).
    * At 100% the bar fills the full track and switches from `bg-info`
      (blue) to `bg-success` (green) — see `:completed`.
    * When `available: false` the play button is replaced with a disabled
      "Offline" pill — see `:offline`.
    * When `detail_view == :info` the secondary toggle reads "Back"
      instead of "More info" — see `:info_view_open`.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.Components.Detail.PlayCard.play_card/1
  def render_source, do: :function
  def layout, do: :one_column

  def template do
    """
    <div class="w-full max-w-3xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :ready_to_play,
        description:
          "Fresh content, no progress recorded. The progress bar is hidden " <>
            "(it only renders when `percent > 0`); the primary CTA reads \"Play\".",
        attributes: %{
          on_play: "play",
          target_id: "entity-1",
          label: "Play",
          percent: 0,
          remaining_text: nil,
          available: true,
          detail_view: :main
        }
      },
      %Variation{
        id: :in_progress_low,
        description:
          "Small amount of progress (8%) — verifies the thin bar still " <>
            "renders a visible sliver without collapsing to zero width.",
        attributes: %{
          on_play: "play",
          target_id: "entity-2",
          label: "Resume",
          percent: 8,
          remaining_text: "1h 55m left",
          available: true,
          detail_view: :main
        }
      },
      %Variation{
        id: :in_progress_mid,
        description:
          "Mid-watch (~50%) — the happy-path \"continue watching\" state. " <>
            "Bar uses `bg-info` (blue), remaining-text sits to its right.",
        attributes: %{
          on_play: "play",
          target_id: "entity-3",
          label: "Resume Episode 5",
          percent: 50,
          remaining_text: "24m left",
          available: true,
          detail_view: :main
        }
      },
      %Variation{
        id: :in_progress_high,
        description:
          "Near-end progress (95%) — pins that the filled portion never " <>
            "overflows the track even at the high end of the range.",
        attributes: %{
          on_play: "play",
          target_id: "entity-4",
          label: "Resume",
          percent: 95,
          remaining_text: "6m left",
          available: true,
          detail_view: :main
        }
      },
      %Variation{
        id: :completed,
        description:
          "Fully watched (100%). The bar fills the full track and switches " <>
            "from `bg-info` to `bg-success` (green); the CTA flips to " <>
            "\"Watch again\".",
        attributes: %{
          on_play: "play",
          target_id: "entity-5",
          label: "Watch again",
          percent: 100,
          remaining_text: nil,
          available: true,
          detail_view: :main
        }
      },
      %Variation{
        id: :no_remaining_text,
        description:
          "In-progress with `remaining_text: nil` — the bar still renders " <>
            "but the right-hand text slot is omitted entirely.",
        attributes: %{
          on_play: "play",
          target_id: "entity-6",
          label: "Resume",
          percent: 35,
          remaining_text: nil,
          available: true,
          detail_view: :main
        }
      },
      %Variation{
        id: :offline,
        description:
          "Storage offline (`available: false`) — the primary play button " <>
            "is replaced with a disabled \"Offline\" pill carrying the " <>
            "explanatory tooltip. The \"More info\" toggle still works.",
        attributes: %{
          on_play: "play",
          target_id: "entity-7",
          label: "Play",
          percent: 0,
          remaining_text: nil,
          available: false,
          detail_view: :main
        }
      },
      %Variation{
        id: :offline_in_progress,
        description:
          "Storage offline mid-watch — the progress bar still renders " <>
            "(playback state is independent of availability) but the CTA " <>
            "is the disabled \"Offline\" pill.",
        attributes: %{
          on_play: "play",
          target_id: "entity-8",
          label: "Resume",
          percent: 42,
          remaining_text: "1h 12m left",
          available: false,
          detail_view: :main
        }
      },
      %Variation{
        id: :info_view_open,
        description:
          "`detail_view: :info` — the secondary toggle's label flips from " <>
            ~s("More info" to "Back" so users can return to the main view.),
        attributes: %{
          on_play: "play",
          target_id: "entity-9",
          label: "Resume",
          percent: 33,
          remaining_text: "1h 28m left",
          available: true,
          detail_view: :info
        }
      }
    ]
  end
end
