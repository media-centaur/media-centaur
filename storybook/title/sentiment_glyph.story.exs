defmodule MediaCentaurWeb.Storybook.Title.SentimentGlyph do
  @moduledoc """
  The one rendering of a review's sentiment as a glyph: a thumbs down,
  a thumbs up, a filled heart in `--color-love`. Every surface that
  shows a sentiment beside a name — a feed entry's first line, a
  Friends card's Reviewed shelf — renders it through here.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Title.Sentiment.sentiment_glyph/1
  def render_source, do: :function

  def template do
    """
    <span class="inline-flex items-center gap-1 text-sm">Sample Friend reviewed <.psb-variation/></span>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :sentiments,
        description: "The three sentiments, in the surrounding text colour except love.",
        variations:
          for sentiment <- [:dislike, :like, :love] do
            %Variation{id: sentiment, attributes: %{sentiment: sentiment}}
          end
      },
      %Variation{
        id: :sized,
        description: "The class sizes and aligns the glyph; the colour stays the glyph's own.",
        attributes: %{sentiment: :love, class: "size-5"}
      }
    ]
  end
end
