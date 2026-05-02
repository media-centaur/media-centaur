defmodule MediaCentarrWeb.Storybook.CoreComponents.Header do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.header/1
  def imports, do: [{MediaCentarrWeb.CoreComponents, button: 1}]
  def render_source, do: :function

  def template do
    """
    <div class="w-full" psb-code-hidden>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :title_only,
        description: "Title only",
        slots: ["Library"]
      },
      %Variation{
        id: :with_subtitle,
        description: "Title + subtitle",
        slots: [
          "Settings",
          """
          <:subtitle>
            Configure how Media Centarr behaves on this device.
          </:subtitle>
          """
        ]
      },
      %Variation{
        id: :with_actions,
        description: "Title + actions",
        slots: [
          "Watch History",
          """
          <:actions>
            <.button>Clear</.button>
          </:actions>
          """
        ]
      },
      %Variation{
        id: :full,
        description: "Title + subtitle + actions",
        slots: [
          "Library",
          """
          <:subtitle>
            Browse everything ready to watch.
          </:subtitle>
          """,
          """
          <:actions>
            <.button>Refresh</.button>
          </:actions>
          """
        ]
      },
      %Variation{
        id: :long_title,
        description: "Long title that wraps",
        slots: [
          "A Very Long Section Title That Demonstrates How The Header Wraps When The Text Exceeds A Single Line Of Width"
        ]
      }
    ]
  end
end
