defmodule MediaCentaurWeb.DiscoveryLive.ActivityWordsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords

  test "each kind has a verb, the watched one naming the episode" do
    assert ActivityWords.verb(:review, nil, :friend) == "reviewed"
    assert ActivityWords.verb(:watched, nil, :friend) == "watched"

    assert ActivityWords.verb(:watched, %Episode{season_number: 2, episode_number: 5}, :friend) ==
             "watched S02E05"

    assert ActivityWords.verb(:listing, nil, :friend) == "wants to watch"
  end

  test "the verb agrees with its subject: a friend wants to watch, you want to watch" do
    assert ActivityWords.verb(:listing, nil, :friend) == "wants to watch"
    assert ActivityWords.verb(:listing, nil, :you) == "want to watch"
    assert ActivityWords.verb(:review, nil, :you) == "reviewed"
    assert ActivityWords.verb(:watched, nil, :you) == "watched"

    assert ActivityWords.verb(:watched, %Episode{season_number: 2, episode_number: 5}, :you) ==
             "watched S02E05"
  end

  test "the delete verb's noun" do
    assert ActivityWords.noun(:review) == "review"
    assert ActivityWords.noun(:watched) == "watched activity"
    assert ActivityWords.noun(:listing) == "listing"
  end
end

defmodule MediaCentaurWeb.DiscoveryLive.ActivityWordsSentenceTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords

  test "the sentence for one act names the title, with the episode before it for a series" do
    assert ActivityWords.sentence(:review, nil, "Sample Movie", :friend) == "reviewed Sample Movie"
    assert ActivityWords.sentence(:watched, nil, "Sample Movie", :friend) == "watched Sample Movie"

    assert ActivityWords.sentence(
             :watched,
             %Episode{season_number: 2, episode_number: 5},
             "Sample Show",
             :friend
           ) ==
             "watched S02E05 of Sample Show"

    assert ActivityWords.sentence(:listing, nil, "Sample Show", :friend) == "wants to watch Sample Show"
    assert ActivityWords.sentence(:listing, nil, "Sample Show", :you) == "want to watch Sample Show"
  end

  test "the verb phrase is what the title follows, with of after an episode watch" do
    assert ActivityWords.verb_phrase(:review, nil, :friend) == "reviewed"
    assert ActivityWords.verb_phrase(:watched, nil, :you) == "watched"

    assert ActivityWords.verb_phrase(:watched, %Episode{season_number: 2, episode_number: 5}, :friend) ==
             "watched S02E05 of"

    assert ActivityWords.verb_phrase(:listing, nil, :friend) == "wants to watch"
  end
end
