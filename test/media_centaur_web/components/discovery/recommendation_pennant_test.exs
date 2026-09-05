defmodule MediaCentaurWeb.Components.Discovery.RecommendationPennantTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory, only: [build_activity: 1]

  alias MediaCentaurWeb.Components.Discovery.RecommendationPennant

  defp friend(nickname, sentiment, acted_at \\ ~U[2026-09-01 12:00:00Z]),
    do: %{
      activity: build_activity(%{sentiment: sentiment, acted_at: acted_at}),
      nickname: nickname,
      own?: false
    }

  defp own(sentiment),
    do: %{activity: build_activity(%{sentiment: sentiment}), nickname: nil, own?: true}

  describe "pennants/1" do
    test "nothing for no recommendations" do
      assert RecommendationPennant.pennants([]) == []
    end

    test "one pennant per sentiment, love above like, names in the rows' order with You last" do
      rows = [own(:like), friend("Sam", :like), friend("Nick", :love), friend("Alex", :like)]

      assert RecommendationPennant.pennants(rows) == [
               %{sentiment: :love, names: ["Nick"]},
               %{sentiment: :like, names: ["Sam", "Alex", "You"]}
             ]
    end
  end

  describe "label/1" do
    test "up to two names, then a count" do
      assert RecommendationPennant.label(%{sentiment: :love, names: ["Nick"]}) == "Nick"
      assert RecommendationPennant.label(%{sentiment: :love, names: ["Nick", "Sam"]}) == "Nick, Sam"
      assert RecommendationPennant.label(%{sentiment: :like, names: ["Nick", "Sam", "You"]}) == "Nick +2"
    end
  end

  describe "tooltip/1" do
    test "reads as a sentence" do
      assert RecommendationPennant.tooltip(%{sentiment: :love, names: ["Nick"]}) == "Nick loves this"
      assert RecommendationPennant.tooltip(%{sentiment: :like, names: ["Nick"]}) == "Nick likes this"
      assert RecommendationPennant.tooltip(%{sentiment: :like, names: ["You"]}) == "You like this"

      assert RecommendationPennant.tooltip(%{sentiment: :love, names: ["Nick", "Sam", "You"]}) ==
               "Nick, Sam and you love this"
    end
  end
end
