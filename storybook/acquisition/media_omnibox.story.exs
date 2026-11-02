defmodule MediaCentaurWeb.Storybook.Acquisition.MediaOmnibox do
  @moduledoc """
  Discovery's search box (UIDR-014, amended) — "What do you want to
  watch?" over the hero's artwork, the placeholder alone. The results
  answer flat below it, outside this component (the MediaResults
  section).
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Acquisition.MediaOmnibox.media_omnibox/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :resting,
        description: "Fresh page — nothing typed, the placeholder alone.",
        attributes: %{}
      },
      %Variation{
        id: :typed,
        description: "A query in the box — the in-input clear X appears at the far right.",
        attributes: %{query: "nosferatu"}
      }
    ]
  end
end
