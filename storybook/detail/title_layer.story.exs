defmodule MediaCentaurWeb.Storybook.Detail.TitleLayer do
  @moduledoc """
  The shared 21:9 identity frame — logo or logotype title plus optional
  tagline, seated bottom-left over the panel backdrop. Worn by the owned
  detail hero and the plan modal's movie confirm.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Detail.TitleLayer.title_layer/1
  def render_source, do: :function

  # The frame is transparent — the backdrop lives at the caller's panel
  # level. Stand a dark panel in so the shadowed text reads as it does
  # over real artwork.
  def template do
    """
    <div class="relative overflow-hidden rounded-xl" style="background: linear-gradient(135deg, oklch(30% 0.05 264), oklch(12% 0.02 264))">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :title_and_tagline,
        description: "No logo — the title logotype with a tagline beneath.",
        attributes: %{
          title: "Sample Movie",
          tagline: "Every confirmation counts."
        }
      },
      %Variation{
        id: :placeholder,
        description: "No backdrop behind the frame (`placeholder?`) — the quiet glass film-icon fill.",
        attributes: %{
          title: "Sample Movie",
          placeholder?: true
        }
      },
      %Variation{
        id: :with_actions,
        description: "Top-right actions slot (the detail hero's tracking bell lives here).",
        attributes: %{title: "Sample Show"},
        slots: [
          """
          <:actions><button type="button" class="btn btn-ghost btn-sm btn-circle">🔔</button></:actions>
          """
        ]
      }
    ]
  end
end
