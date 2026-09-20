defmodule MediaCentaurWeb.Live.TitleDetailHost.TmdbEventsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Live.TitleDetailHost.TmdbEvents

  test "a 304 reads as nothing changed" do
    assert {:info, "Checked TMDB — nothing has changed."} =
             TmdbEvents.check_flash({:ok, :unchanged, %{}})
  end

  test "a replaced payload reads as updated" do
    assert {:info, "Updated from TMDB."} = TmdbEvents.check_flash({:ok, :changed, %{}})
  end

  test "a failed request says TMDB did not answer" do
    assert {:error, "TMDB didn't answer — try again later."} =
             TmdbEvents.check_flash({:error, :econnrefused})
  end
end
