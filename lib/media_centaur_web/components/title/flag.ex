defmodule MediaCentaurWeb.Components.Title.Flag do
  @moduledoc """
  The flag vocabulary every social glyph shares: which flag an activity
  shows as, the glyph for a flag at a weight, and the order flags are
  drawn in.

  A review shows its sentiment — love, like, dislike — or the reviewed
  flag when it gives none; a watch and a listing show themselves. The
  order is love, like, dislike, reviewed, watched, listing. `:outline`
  is the heroicons outline set — the plain grade's line drawing, love a
  hollow heart like the others — and `:solid` the same glyph from the
  solid set, which silver and gold draw in metal (`Title.SocialGlyph`).

  Pure vocabulary, not a function component — no story.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Pure vocabulary, not a function component"

  alias MediaCentaur.Activities.Activity

  @type flag :: :love | :like | :dislike | :review | :watched | :listing
  @type weight :: :outline | :solid

  @order [:love, :like, :dislike, :review, :watched, :listing]

  @doc "The flag an activity shows as: a review by its sentiment, or reviewed when it gives none; the other kinds as themselves."
  @spec flag(Activity.t()) :: flag()
  def flag(%Activity{kind: :review, sentiment: nil}), do: :review
  def flag(%Activity{kind: :review, sentiment: sentiment}), do: sentiment
  def flag(%Activity{kind: kind}), do: kind

  @doc """
  The heroicon for a flag, at the outline weight or from the solid set.
  Literal names, one per clause: Tailwind's icon scanner emits CSS only
  for the names it reads in source, so a name built at runtime would
  draw nothing.
  """
  @spec glyph(flag(), weight()) :: String.t()
  def glyph(flag, weight \\ :outline)
  def glyph(:love, :outline), do: "hero-heart"
  def glyph(:love, :solid), do: "hero-heart-solid"
  def glyph(:like, :outline), do: "hero-hand-thumb-up"
  def glyph(:like, :solid), do: "hero-hand-thumb-up-solid"
  def glyph(:dislike, :outline), do: "hero-hand-thumb-down"
  def glyph(:dislike, :solid), do: "hero-hand-thumb-down-solid"
  def glyph(:review, :outline), do: "hero-chat-bubble-bottom-center-text"
  def glyph(:review, :solid), do: "hero-chat-bubble-bottom-center-text-solid"
  def glyph(:watched, :outline), do: "hero-eye"
  def glyph(:watched, :solid), do: "hero-eye-solid"
  def glyph(:listing, :outline), do: "hero-bookmark"
  def glyph(:listing, :solid), do: "hero-bookmark-solid"

  @doc "The order flags are drawn in: love, like, dislike, reviewed, watched, listing."
  @spec order() :: [flag()]
  def order, do: @order

  @doc "The given flags in order, each once."
  @spec sort([flag()]) :: [flag()]
  def sort(flags), do: Enum.filter(@order, &(&1 in flags))
end
