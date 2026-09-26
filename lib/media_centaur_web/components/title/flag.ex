defmodule MediaCentaurWeb.Components.Title.Flag do
  @moduledoc """
  The flag vocabulary shared by the pennant (UIDR-037) and a person
  card's act slots (UIDR-046): which flag an activity flies, the glyph
  for a flag at a weight, the mast order, and the act slot a flag is
  drawn in.

  A review flies its sentiment — love, like, dislike — or the reviewed
  flag when it gives none; a watch and a listing fly themselves. The
  mast order is love, like, dislike, reviewed, watched, listing. The
  sentiment glyphs are `Title.Sentiment`'s, the one map every surface
  shares; the bubble, the eye and the bookmark are the pennant's three.
  `:solid` names the same glyph from the heroicons solid set, which the
  act slots use; love is solid at every weight.

  Pure vocabulary, not a function component — no story.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Pure vocabulary, not a function component"

  alias MediaCentaur.Activities.Activity
  alias MediaCentaurWeb.Components.Title.Sentiment

  @type flag :: :love | :like | :dislike | :review | :watched | :listing
  @type weight :: :outline | :solid

  @mast_order [:love, :like, :dislike, :review, :watched, :listing]

  @doc "The flag an activity flies: a review by its sentiment, or reviewed when it gives none; the other kinds as themselves."
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

  def glyph(sentiment, weight) when sentiment in [:love, :like, :dislike],
    do: Sentiment.glyph(sentiment, weight)

  def glyph(:review, :outline), do: "hero-chat-bubble-bottom-center-text"
  def glyph(:review, :solid), do: "hero-chat-bubble-bottom-center-text-solid"
  def glyph(:watched, :outline), do: "hero-eye"
  def glyph(:watched, :solid), do: "hero-eye-solid"
  def glyph(:listing, :outline), do: "hero-bookmark"
  def glyph(:listing, :solid), do: "hero-bookmark-solid"

  @doc "The mast order: love, like, dislike, reviewed, watched, listing."
  @spec mast_order() :: [flag()]
  def mast_order, do: @mast_order

  @doc "The given flags in mast order, each once."
  @spec sort_by_mast([flag()]) :: [flag()]
  def sort_by_mast(flags), do: Enum.filter(@mast_order, &(&1 in flags))
end
