defmodule MediaCentaurWeb.Storybook.Detail.PlayCard do
  @moduledoc """
  The detail modal's play control — the Play/Resume button and the view
  controls sharing its line.

  Play is the only primary button in the modal. The view controls that share
  its line arrive through the `controls` slot (`Detail.ViewControls`), which
  has its own story — so this component has exactly one job and no sub-view
  state to render.

  The card carries **no progress element** (UIDR-024): every subject's
  watched fraction lives in the hero orientation hairline
  (`MediaCentaurWeb.Components.ProgressHairline`), and the remaining time is
  a metadata-line item. The former percent/remaining row was retired from
  this contract, not hidden.

  Pure presentation: callers pre-compute `label` and `available` (typically
  via `Detail.Logic.playback_props/3`) and pass them in. No context lookups
  happen at render time, which is why the variations below are flat literal
  data with no fakes or stubs.

  Visual contract pinned by the variations:

    * The label is the only per-state text — "Play", "Resume Episode 5",
      "Watch again".
    * When `available: false` the play button is replaced with a disabled
      "Offline" pill carrying the explanatory tooltip — see `:offline`.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.PlayCard.play_card/1
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
        description: "Fresh content — the primary CTA reads \"Play\".",
        attributes: %{
          on_play: "play",
          target_id: "entity-1",
          label: "Play",
          available: true
        }
      },
      %Variation{
        id: :resume,
        description:
          "Mid-watch — the label carries the resume state; the fraction " <>
            "itself renders in the hero hairline, not here.",
        attributes: %{
          on_play: "play",
          target_id: "entity-2",
          label: "Resume",
          available: true
        }
      },
      %Variation{
        id: :resume_episode,
        description:
          "TV resume label naming the next episode — the longest realistic " <>
            "label the row must accommodate beside its view controls.",
        attributes: %{
          on_play: "play",
          target_id: "entity-3",
          label: "Resume Episode 5",
          available: true
        }
      },
      %Variation{
        id: :watch_again,
        description: "Fully watched — the CTA flips to \"Watch again\".",
        attributes: %{
          on_play: "play",
          target_id: "entity-4",
          label: "Watch again",
          available: true
        }
      },
      %Variation{
        id: :offline,
        description:
          "Storage offline (`available: false`) — the primary play button " <>
            "is replaced with a disabled \"Offline\" pill carrying the " <>
            "explanatory tooltip.",
        attributes: %{
          on_play: "play",
          target_id: "entity-5",
          label: "Play",
          available: false
        }
      }
    ]
  end
end
