defmodule MediaCentarrWeb.Storybook.CoreComponents.List do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentarrWeb.CoreComponents.list/1
  def render_source, do: :function

  def template do
    """
    <div class="-mt-14 py-8" psb-code-hidden>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :single_item,
        slots: [
          ~s|<:item title="Title">Sample Show</:item>|
        ]
      },
      %Variation{
        id: :many_items,
        slots:
          for {label, value} <- [
                {"Title", "Sample Show"},
                {"Year", "2024"},
                {"Genre", "Drama"},
                {"Runtime", "48 min"},
                {"Rating", "TV-14"}
              ] do
            ~s|<:item title="#{label}">#{value}</:item>|
          end
      },
      %Variation{
        id: :long_value,
        slots:
          for {label, value} <- [
                {"Title", "Sample Show With A Considerably Longer Display Title"},
                {"Tags",
                 "drama, mystery, slow-burn, ensemble cast, character study, period piece, critically acclaimed, multi-season arc, anthology format, award-winning"}
              ] do
            ~s|<:item title="#{label}">#{value}</:item>|
          end
      }
    ]
  end
end
