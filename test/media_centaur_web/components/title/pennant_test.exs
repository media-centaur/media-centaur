defmodule MediaCentaurWeb.Components.Title.PennantTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.TestFactory, only: [build_activity: 1]

  alias MediaCentaurWeb.Components.Title.Pennant

  defp friend(nickname, attrs),
    do: %{activity: build_activity(Map.new(attrs)), nickname: nickname, own?: false}

  defp own(sentiment),
    do: %{activity: build_activity(%{sentiment: sentiment}), nickname: nil, own?: true}

  describe "mast/1" do
    test "nothing for no activity" do
      assert Pennant.mast([]) == []
    end

    test "one pennant per flag in mast order, names in the rows' order with You last" do
      rows = [
        friend("Pat", kind: :listing),
        own(:like),
        friend("Sam", sentiment: :like),
        friend("Nick", sentiment: :love),
        friend("Alex", sentiment: :like),
        friend("Nick", kind: :watched)
      ]

      assert Pennant.mast(rows) == [
               %{flag: :love, names: ["Nick"]},
               %{flag: :like, names: ["Sam", "Alex", "You"]},
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
