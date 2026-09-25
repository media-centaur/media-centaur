defmodule MediaCentaurWeb.Components.Title.Sentiment do
  @moduledoc """
  The one rendering of a review's sentiment as a glyph: a thumbs down
  for dislike, a thumbs up for like, a filled heart for love — love in
  `--color-love`, the one warm hue outside the health palette, the other
  two in the surrounding text colour. Every surface that shows a
  sentiment beside a name renders it through here — a feed row's first
  line, a Friends card's Reviewed shelf — so the glyphs never drift
  apart; the pennant, which paints its own fill, composes `glyph/1` into
  its own icon, and the Review modal's choices are pennants.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaur.Activities.Activity

  attr :sentiment, :atom, required: true, values: [:dislike, :like, :love]

  attr :class, :string,
    default: "size-3.5",
    doc: "sizing; the glyph sits inline-block, vertical-align middle, in the text run"

  def sentiment_glyph(assigns) do
    ~H"""
    <span data-sentiment={@sentiment} class={[@sentiment == :love && "text-love"]}>
      <.icon name={glyph(@sentiment)} class={@class} />
    </span>
    """
  end

  @doc """
  The heroicon for a sentiment, at the outline weight or from the solid
  set (the act slots' weight). Love is a filled heart at every weight.
  Literal names, one per clause: Tailwind's icon scanner emits CSS only
  for the names it reads in source.
  """
  @spec glyph(Activity.sentiment(), :outline | :solid) :: String.t()
  def glyph(sentiment, weight \\ :outline)
  def glyph(:dislike, :outline), do: "hero-hand-thumb-down"
  def glyph(:dislike, :solid), do: "hero-hand-thumb-down-solid"
  def glyph(:like, :outline), do: "hero-hand-thumb-up"
  def glyph(:like, :solid), do: "hero-hand-thumb-up-solid"
  def glyph(:love, _weight), do: "hero-heart-solid"
end
