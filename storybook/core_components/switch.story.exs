defmodule MediaCentaurWeb.Storybook.CoreComponents.Switch do
  @moduledoc """
  The app's one switch: a toggle glyph and its words as one click
  (`role="switch"`). The toggle leads, compact, for a switch inside a
  card or a block — the tracking block's rows, the person card's foot;
  it trails, right-aligned at the Settings kit's size, for a Settings
  row. Held — no event — it takes no click, dims, and its description
  says why.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Switch.switch/1
  def render_source, do: :function

  @block ~s(<div class="max-w-sm"><.psb-variation/></div>)
  @row ~s(<div class="max-w-xl glass-surface rounded-xl p-2"><.psb-variation/></div>)
  @in_block "-mx-2 px-2 py-1.5"

  def variations do
    [
      %Variation{
        id: :leading,
        description: "The toggle before the words, with a description: the tracking block's row",
        attributes: %{
          id: "switch-leading",
          label: "Auto-grab",
          description: "Plans episodes as they air and waits for your approval.",
          checked: true,
          event: "set_rung",
          values: %{"choice" => "follow", "ref" => "tv_series-1399"},
          class: @in_block
        },
        template: @block
      },
      %Variation{
        id: :leading_label_only,
        description: "The label alone: the person card's foot",
        attributes: %{
          id: "switch-label-only",
          label: "Show their picture",
          checked: true,
          event: "set_show_avatar",
          values: %{"pubkey" => "f9308a019258c310", "show" => "false"},
          class: @in_block
        },
        template: @block
      },
      %Variation{
        id: :trailing,
        description:
          "The words first at the Settings kit's size, the toggle right-aligned: a Settings row",
        attributes: %{
          layout: :trailing,
          label: "Share what you watch",
          description: "Friends see a movie or an episode when you finish it.",
          checked: true,
          event: "toggle_share_watched",
          class: "py-2.5 px-3.5"
        },
        template: @row
      },
      %Variation{
        id: :held,
        description:
          "Held: no event, so no click and aria-disabled; dimmed, and the description says why",
        attributes: %{
          id: "switch-held",
          label: "Notify you via Coming up",
          description: "Stays on while auto-grab is on.",
          checked: true,
          class: @in_block
        },
        template: @block
      },
      %VariationGroup{
        id: :on_off,
        description: "On and off, in each layout",
        template: @block,
        variations:
          for layout <- [:leading, :trailing], checked <- [true, false] do
            %Variation{
              id: :"#{layout}_#{if checked, do: "on", else: "off"}",
              attributes: %{
                id: "switch-#{layout}-#{checked}",
                layout: layout,
                label: "Sample switch",
                description: "What the app does while it is on.",
                checked: checked,
                event: "toggle_sample",
                class: @in_block
              }
            }
          end
      }
    ]
  end
end
