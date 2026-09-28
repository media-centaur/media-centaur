defmodule MediaCentaurWeb.Components.Title.FlagTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.TestFactory, only: [build_activity: 1]

  alias MediaCentaurWeb.Components.Title.Flag

  test "a review flies its sentiment, or reviewed when it gives none; the other kinds fly themselves" do
    assert Flag.flag(build_activity(%{kind: :review, sentiment: :love})) == :love
    assert Flag.flag(build_activity(%{kind: :review, sentiment: :like})) == :like
    assert Flag.flag(build_activity(%{kind: :review, sentiment: :dislike})) == :dislike
    assert Flag.flag(build_activity(%{kind: :review, sentiment: nil})) == :review
    assert Flag.flag(build_activity(%{kind: :watched, sentiment: nil})) == :watched
    assert Flag.flag(build_activity(%{kind: :listing, sentiment: nil})) == :listing
  end

  test "the order is love, like, dislike, reviewed, watched, listing, and every flag has a glyph" do
    assert Flag.order() == [:love, :like, :dislike, :review, :watched, :listing]
    assert Enum.all?(Flag.order(), &String.starts_with?(Flag.glyph(&1), "hero-"))
    assert Flag.glyph(:watched) == "hero-eye"
  end

  test "the outline weight is the outline set with no exception: love is a hollow heart" do
    assert Flag.glyph(:love) == "hero-heart"
    assert Flag.glyph(:like) == "hero-hand-thumb-up"
    assert Flag.glyph(:dislike) == "hero-hand-thumb-down"
    assert Flag.glyph(:review) == "hero-chat-bubble-bottom-center-text"
    assert Flag.glyph(:watched) == "hero-eye"
    assert Flag.glyph(:listing) == "hero-bookmark"
  end

  test "the solid weight is the same glyph from the solid set" do
    assert Flag.glyph(:love, :solid) == "hero-heart-solid"
    assert Flag.glyph(:like, :solid) == "hero-hand-thumb-up-solid"
    assert Flag.glyph(:dislike, :solid) == "hero-hand-thumb-down-solid"
    assert Flag.glyph(:review, :solid) == "hero-chat-bubble-bottom-center-text-solid"
    assert Flag.glyph(:watched, :solid) == "hero-eye-solid"
    assert Flag.glyph(:listing, :solid) == "hero-bookmark-solid"
  end

  test "sort/1 puts flags in order and drops repeats" do
    assert Flag.sort([:watched, :love, :watched, :review]) == [:love, :review, :watched]
  end
end
