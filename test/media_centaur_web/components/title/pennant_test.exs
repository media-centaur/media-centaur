defmodule MediaCentaurWeb.Components.Title.PennantTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.TestFactory, only: [build_activity: 1]

  alias MediaCentaurWeb.Components.Title.Pennant

  defp friend(nickname, attrs),
    do: %{activity: build_activity(Map.new(attrs)), nickname: nickname, own?: false}

  defp own(sentiment),
    do: %{activity: build_activity(%{sentiment: sentiment}), nickname: nil, own?: true}

  describe "flag/1" do
    test "a review flies its sentiment, or reviewed when it gives none; the other kinds fly themselves" do
      assert Pennant.flag(build_activity(%{kind: :review, sentiment: :love})) == :love
      assert Pennant.flag(build_activity(%{kind: :review, sentiment: :like})) == :like
      assert Pennant.flag(build_activity(%{kind: :review, sentiment: :dislike})) == :dislike
      assert Pennant.flag(build_activity(%{kind: :review, sentiment: nil})) == :review
      assert Pennant.flag(build_activity(%{kind: :watched, sentiment: nil})) == :watched
      assert Pennant.flag(build_activity(%{kind: :listing, sentiment: nil})) == :listing
    end
  end

  describe "mast/1" do
    test "nothing for no activity" do
      assert Pennant.mast([]) == []
    end

    test "one pennant per flag in mast order, names in the rows' order with You last" do
      rows = [
        friend("Pat", kind: :listing),
        own(:like),
        friend("Sam", sentiment: :like),
        friend("Kim", sentiment: nil),
        friend("Nick", sentiment: :love),
        friend("Alex", sentiment: :like),
        friend("Jo", sentiment: :dislike),
        friend("Nick", kind: :watched)
      ]

      assert Pennant.mast(rows) == [
               %{flag: :love, names: ["Nick"]},
               %{flag: :like, names: ["Sam", "Alex", "You"]},
               %{flag: :dislike, names: ["Jo"]},
               %{flag: :review, names: ["Kim"]},
               %{flag: :watched, names: ["Nick"]},
               %{flag: :listing, names: ["Pat"]}
             ]
    end
  end

  describe "label/1" do
    test "up to two names, then a count" do
      assert Pennant.label(%{flag: :love, names: ["Nick"]}) == "Nick"
      assert Pennant.label(%{flag: :love, names: ["Nick", "Sam"]}) == "Nick, Sam"
      assert Pennant.label(%{flag: :like, names: ["Nick", "Sam", "You"]}) == "Nick +2"
    end
  end

  describe "tooltip/1" do
    test "reads as a sentence" do
      assert Pennant.tooltip(%{flag: :love, names: ["Nick"]}) == "Nick loves this"
      assert Pennant.tooltip(%{flag: :like, names: ["Nick"]}) == "Nick likes this"
      assert Pennant.tooltip(%{flag: :like, names: ["You"]}) == "You like this"
      assert Pennant.tooltip(%{flag: :dislike, names: ["Nick"]}) == "Nick dislikes this"
      assert Pennant.tooltip(%{flag: :dislike, names: ["Nick", "You"]}) == "Nick and you dislike this"
      assert Pennant.tooltip(%{flag: :review, names: ["Nick"]}) == "Nick reviewed this"
      assert Pennant.tooltip(%{flag: :review, names: ["Nick", "Sam"]}) == "Nick and Sam reviewed this"

      assert Pennant.tooltip(%{flag: :love, names: ["Nick", "Sam", "You"]}) ==
               "Nick, Sam and you love this"

      assert Pennant.tooltip(%{flag: :watched, names: ["Nick"]}) == "Nick watched this"
      assert Pennant.tooltip(%{flag: :watched, names: ["Nick", "Sam"]}) == "Nick and Sam watched this"
      assert Pennant.tooltip(%{flag: :listing, names: ["Nick"]}) == "Nick wants to watch this"

      assert Pennant.tooltip(%{flag: :listing, names: ["Nick", "Sam"]}) ==
               "Nick and Sam want to watch this"
    end
  end
end
