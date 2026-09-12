defmodule MediaCentaurWeb.Components.Title.Sentiment do
  @moduledoc """
  The one rendering of a review's sentiment as a glyph: a thumbs down
  for dislike, a thumbs up for like, a filled heart for love — love in
  `--color-love`, the one warm hue outside the health palette, the other
  two in the surrounding text colour. Every surface that shows a
  sentiment beside a name renders it through here — a feed entry's first
  line, a Friends card's Reviewed shelf — so the glyphs never drift
  apart; the pennant, which paints its own fill, composes `glyph/1` into
  its own icon, and the Review modal's choices are pennants.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Activities.Activity

  attr :sentiment, :atom, required: true, values: [:dislike, :like, :love]
  attr :class, :string, default: "size-3.5", doc: "sizing and alignment; the colour is the glyph's own"

  def sentiment_glyph(assigns) do
    ~H"""
    <span data-sentiment={@sentiment} class={["inline-flex", @sentiment == :love && "text-love"]}>
      <.icon name={glyph(@sentiment)} class={@class} />
    </span>
    """
  end

  @doc "The heroicon for a sentiment."
  @spec glyph(Activity.sentiment()) :: String.t()
  def glyph(:dislike), do: "hero-hand-thumb-down"
  def glyph(:like), do: "hero-hand-thumb-up"
  def glyph(:love), do: "hero-heart-solid"
end
