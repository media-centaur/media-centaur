defmodule MediaCentaurWeb.MediaTokenTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.MediaToken

  @player "a0a0a0a0-0000-4000-8000-000000000001"
  @presence "b1b1b1b1-0000-4000-8000-000000000002"

  test "a token names one player and one file and verifies back to them" do
    token = MediaToken.sign(@player, @presence)
    assert MediaToken.verify(token) == {:ok, {@player, @presence}}
  end

  test "a tampered or foreign token is invalid; no token is missing" do
    token = MediaToken.sign(@player, @presence)
    assert MediaToken.verify(token <> "x") == {:error, :invalid}
    assert MediaToken.verify("not-a-token") == {:error, :invalid}
    assert MediaToken.verify(nil) == {:error, :missing}
  end

  test "a token is good for twelve hours" do
    assert MediaToken.max_age() == 12 * 60 * 60
  end
end
