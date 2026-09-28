defmodule MediaCentaurWeb.DiscoveryLive.GradeTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.DiscoveryLive.Grade

  # Each case: the flag, how many distinct people flew each flag on the
  # title, how many distinct people engaged with it at all, the grade.
  describe "grade/3" do
    test "one person is plain whatever the share" do
      assert Grade.grade(:like, %{like: 1}, 1) == :plain
      assert Grade.grade(:watched, %{watched: 1}, 1) == :plain
    end

    test "an opinion's share is of the verdicts on the title: half is silver, two-thirds gold" do
      assert Grade.grade(:like, %{like: 2}, 2) == :gold
      assert Grade.grade(:like, %{like: 3, dislike: 1}, 4) == :gold
      assert Grade.grade(:dislike, %{like: 3, dislike: 1}, 4) == :plain
      assert Grade.grade(:like, %{like: 2, dislike: 2}, 4) == :silver
      assert Grade.grade(:dislike, %{like: 2, dislike: 2}, 4) == :silver
      assert Grade.grade(:like, %{like: 3, love: 2}, 5) == :silver
      assert Grade.grade(:love, %{like: 3, love: 2}, 5) == :plain
      assert Grade.grade(:like, %{like: 2, love: 1, dislike: 2}, 5) == :plain
    end

    test "people who only watched, listed or reviewed without a verdict do not dilute an opinion" do
      assert Grade.grade(:like, %{like: 2, watched: 3, listing: 4, review: 1}, 10) == :gold
    end

    test "watched's share is of everyone who engaged with the title" do
      assert Grade.grade(:watched, %{watched: 3, listing: 1}, 4) == :gold
      assert Grade.grade(:watched, %{watched: 2, listing: 2}, 4) == :silver
      assert Grade.grade(:watched, %{watched: 2, listing: 5}, 7) == :plain
    end

    test "reviewed without a verdict and listing are never graded" do
      assert Grade.grade(:review, %{review: 3}, 3) == :plain
      assert Grade.grade(:listing, %{listing: 5}, 5) == :plain
    end
  end
end
