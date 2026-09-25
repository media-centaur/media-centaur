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

  test "mast order is love, like, dislike, reviewed, watched, listing, and every flag has a glyph" do
    assert Flag.mast_order() == [:love, :like, :dislike, :review, :watched, :listing]
    assert Enum.all?(Flag.mast_order(), &String.starts_with?(Flag.glyph(&1), "hero-"))
    assert Flag.glyph(:love) == "hero-heart-solid"
    assert Flag.glyph(:watched) == "hero-eye"
  end

  test "the solid weight is the same glyph from the solid set; love is solid at every weight" do
    assert Flag.glyph(:watched, :solid) == "hero-eye-solid"
    assert Flag.glyph(:like, :solid) == "hero-hand-thumb-up-solid"
    assert Flag.glyph(:listing, :solid) == "hero-bookmark-solid"
    assert Flag.glyph(:love, :solid) == "hero-heart-solid"
  end

  test "sort_by_mast/1 orders flags and drops repeats" do
    assert Flag.sort_by_mast([:watched, :love, :watched, :review]) == [:love, :review, :watched]
  end

  test "slot/1 is the act slot a flag is drawn in: the four opinions in 1, the eye in 2, the bookmark in 3" do
    assert Enum.map([:love, :like, :dislike, :review], &Flag.slot/1) == [1, 1, 1, 1]
    assert Flag.slot(:watched) == 2
    assert Flag.slot(:listing) == 3
  end
end
