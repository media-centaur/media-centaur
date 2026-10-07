defmodule MediaCentaurWeb.ProfileController.ReturnToTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.ProfileController.ReturnTo

  test "a local path returns; anything else, the picker itself included, goes home" do
    assert ReturnTo.local_path("/library") == "/library"
    assert ReturnTo.local_path("/settings?section=tmdb") == "/settings?section=tmdb"
    assert ReturnTo.local_path("/") == "/"
    assert ReturnTo.local_path(nil) == "/"
    assert ReturnTo.local_path("") == "/"
    assert ReturnTo.local_path("//evil.example") == "/"
    assert ReturnTo.local_path("/\\evil.example") == "/"
    assert ReturnTo.local_path("https://evil.example/") == "/"
    assert ReturnTo.local_path("/profiles") == "/"
    assert ReturnTo.local_path("/profiles?return_to=%2Flibrary") == "/"
  end
end
