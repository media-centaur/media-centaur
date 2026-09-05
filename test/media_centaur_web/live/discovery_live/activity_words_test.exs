defmodule MediaCentaurWeb.DiscoveryLive.ActivityWordsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords

  test "each kind has a verb, the watched one naming the episode" do
    assert ActivityWords.verb(:recommendation, nil) == "recommended"
    assert ActivityWords.verb(:watched, nil) == "watched"

    assert ActivityWords.verb(:watched, %Episode{season_number: 2, episode_number: 5}) ==
             "watched S02E05"

    assert ActivityWords.verb(:tracking, nil) == "started tracking"
  end

  test "the delete verb's noun" do
    assert ActivityWords.noun(:recommendation) == "recommendation"
    assert ActivityWords.noun(:watched) == "watched activity"
    assert ActivityWords.noun(:tracking) == "tracking activity"
  end

  test "a statement joins the actor and the verb" do
    assert ActivityWords.statement("You", :tracking, nil) == "You started tracking"

    assert ActivityWords.statement("Sam", :watched, %Episode{season_number: 1, episode_number: 12}) ==
             "Sam watched S01E12"
  end
end
