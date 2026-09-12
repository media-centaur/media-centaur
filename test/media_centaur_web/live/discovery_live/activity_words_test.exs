defmodule MediaCentaurWeb.DiscoveryLive.ActivityWordsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords

  test "each kind has a verb, the watched one naming the episode" do
    assert ActivityWords.verb(:review, nil) == "reviewed"
    assert ActivityWords.verb(:watched, nil) == "watched"

    assert ActivityWords.verb(:watched, %Episode{season_number: 2, episode_number: 5}) ==
             "watched S02E05"

    assert ActivityWords.verb(:listing, nil) == "wants to watch"
  end

  test "the delete verb's noun" do
    assert ActivityWords.noun(:review) == "review"
    assert ActivityWords.noun(:watched) == "watched activity"
    assert ActivityWords.noun(:listing) == "listing"
  end
end

defmodule MediaCentaurWeb.DiscoveryLive.ActivityWordsPresenceTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords

  test "the presence sentence names the title, with the episode before it for a series" do
    assert ActivityWords.presence(:review, nil, "Sample Movie") == "reviewed Sample Movie"
    assert ActivityWords.presence(:watched, nil, "Sample Movie") == "watched Sample Movie"

    assert ActivityWords.presence(:watched, %Episode{season_number: 2, episode_number: 5}, "Sample Show") ==
             "watched S02E05 of Sample Show"

    assert ActivityWords.presence(:listing, nil, "Sample Show") == "wants to watch Sample Show"
  end
end
