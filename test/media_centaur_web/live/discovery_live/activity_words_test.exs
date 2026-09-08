defmodule MediaCentaurWeb.DiscoveryLive.ActivityWordsTest do
  use MediaCentaur.Case, async: true

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
end

defmodule MediaCentaurWeb.DiscoveryLive.ActivityWordsPresenceTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords

  test "the presence sentence names the title, with the episode before it for a series" do
    assert ActivityWords.presence(:recommendation, nil, "Sample Movie") == "recommended Sample Movie"
    assert ActivityWords.presence(:watched, nil, "Sample Movie") == "watched Sample Movie"

    assert ActivityWords.presence(:watched, %Episode{season_number: 2, episode_number: 5}, "Sample Show") ==
             "watched S02E05 of Sample Show"

    assert ActivityWords.presence(:tracking, nil, "Sample Show") == "started tracking Sample Show"
  end
end
