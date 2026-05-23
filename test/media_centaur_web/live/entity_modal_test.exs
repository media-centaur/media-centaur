defmodule MediaCentaurWeb.Live.EntityModalTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.Live.EntityModal

  describe "refresh_artwork_flash/1" do
    test "ok → info" do
      assert {:info, message} = EntityModal.refresh_artwork_flash({:ok, %Oban.Job{}})
      assert message =~ "Refreshing artwork"
    end

    test "no tmdb id → error pointing at Rematch" do
      assert {:error, message} = EntityModal.refresh_artwork_flash({:error, :no_tmdb_id})
      assert message =~ "Rematch"
    end

    test "other error → generic error" do
      assert {:error, _message} = EntityModal.refresh_artwork_flash({:error, :boom})
    end
  end
end
