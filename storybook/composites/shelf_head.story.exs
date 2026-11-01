defmodule MediaCentaurWeb.Storybook.Composites.ShelfHead do
  @moduledoc """
  The line above a shelf on Home and Discovery: the title, and *See all*
  when the shelf has a page of its own.
  """
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.ShelfHead.shelf_head/1
  def render_source, do: :function
  def layout, do: :one_column

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
        id: :with_see_all,
        description: "A shelf with a page of its own — Recently Added over the Library.",
        attributes: %{title: "Recently Added", see_all_href: "/library"}
      },
      %Variation{
        id: :complete_here,
        description: "A shelf that is complete where it is — no link.",
        attributes: %{title: "New Releases"}
      }
    ]
  end
end
