defmodule MediaCentaurWeb.ProfileWordsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.ProfileWords

  test "every refusal a person-record form can meet has words" do
    assert ProfileWords.error(:name_required) == "A profile needs a name"
    assert ProfileWords.error(:name_too_long) == "Names are at most 50 characters"
    assert ProfileWords.error(:bad_image) == "That file is not a picture we can read"
    assert ProfileWords.error(:too_large) == "That picture cannot be made small enough"
    assert ProfileWords.error(:avatar_too_large) == ProfileWords.error(:too_large)
    assert ProfileWords.error(:invalid_hue) == "That colour cannot be used"
    assert ProfileWords.error(:too_many_profiles) == "Eight profiles is the most this install holds"
    assert ProfileWords.error(:last_profile) == "The last profile can't be removed"
  end
end
