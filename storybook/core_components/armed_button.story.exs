defmodule MediaCentaurWeb.Storybook.CoreComponents.ArmedButton do
  @moduledoc """
  Story for `<.armed_button>` — the two-click destructive gesture
  (MC0027 tier 2). Idle it looks like its `variant`; armed it turns
  danger and says what the second click does.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.CoreComponents.armed_button/1
  def render_source, do: :function

  def variations do
    [
      %VariationGroup{
        id: :idle,
        description: "Before the first click, in each idle variant",
        variations:
          for {variant, id} <- [
                {"danger", :danger},
                {"risky", :risky},
                {"dismiss", :dismiss},
                {"destructive_inline", :destructive_inline}
              ] do
            %Variation{
              id: id,
              attributes: %{
                armed: false,
                arm: "noop",
                fire: "noop",
                armed_label: "Click again to delete",
                variant: variant
              },
              slots: ["Delete"]
            }
          end
      },
      %VariationGroup{
        id: :armed,
        description: "After the first click — danger, relabelled, aria-pressed",
        variations:
          for {size, id} <- [{"xs", :armed_xs}, {"sm", :armed_sm}, {"md", :armed_md}, {"lg", :armed_lg}] do
            %Variation{
              id: id,
              attributes: %{
                armed: true,
                arm: "noop",
                fire: "noop",
                armed_label: "Click again to delete",
                size: size
              },
              slots: ["Delete"]
            }
          end
      }
    ]
  end
end
