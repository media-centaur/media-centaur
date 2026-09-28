defmodule MediaCentaurWeb.Storybook.Title.SocialGlyph do
  @moduledoc """
  The social glyph: one flag at its grade — plain (a white line
  drawing), silver or gold (the solid glyph in brushed metal) — as one
  person, two, or three or more did that act on the title (UIDR-046).
  Every surface that shows what people did with a title draws it here.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.SocialGlyph.social_glyph/1
  def render_source, do: :function

  def template do
    """
    <div class="inline-flex p-3" style="--glyph: 28px"><.psb-variation/></div>
    """
  end

  def variations do
    for grade <- [:plain, :silver, :gold] do
      %VariationGroup{
        id: grade,
        description: "Every flag at #{grade}.",
        variations:
          for flag <- [:love, :like, :dislike, :review, :watched, :listing] do
            %Variation{id: flag, attributes: %{flag: flag, grade: grade}}
          end
      }
    end ++
      [
        %Variation{
          id: :inline,
          description: "Sized by a utility in a line of text — a Feed row's sentiment.",
          attributes: %{flag: :love, grade: :plain, class: "size-4 align-middle"},
          template: """
          <span class="text-base text-base-content/80">Sample Friend reviewed <.psb-variation/></span>
          """
        }
      ]
  end
end
