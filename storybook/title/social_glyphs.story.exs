defmodule MediaCentaurWeb.Storybook.Title.SocialGlyphs do
  @moduledoc """
  A title's social glyphs in order, each at its grade, as one inline
  group — the person card's strip, a title row's right edge, the social
  capsule's contents.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.SocialGlyph.social_glyphs/1
  def render_source, do: :function

  def template do
    """
    <div class="inline-flex p-3" style="--glyph: 24px"><.psb-variation/></div>
    """
  end

  def variations do
    [
      %Variation{
        id: :one,
        description: "One act by one person.",
        attributes: %{flags: [:watched], grades: %{watched: :plain}, class: "gap-3"}
      },
      %Variation{
        id: :mixed,
        description: "Two loved it, one liked it, three or more watched it, one wants to watch it.",
        attributes: %{
          flags: [:love, :like, :watched, :listing],
          grades: %{love: :silver, like: :plain, watched: :gold, listing: :plain},
          tips: %{love: "Nick and you love this", watched: "Nick, Sam and you watched this"},
          class: "gap-3"
        }
      },
      %Variation{
        id: :split,
        description: "Opinions never weigh against each other: a like and a dislike each grade alone.",
        attributes: %{
          flags: [:like, :dislike, :review],
          grades: %{like: :gold, dislike: :silver, review: :plain},
          class: "gap-3"
        }
      }
    ]
  end
end
