defmodule MediaCentarr.Playback.SessionsTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Playback.Sessions

  describe "play/1" do
    test "returns {:error, :file_not_found} when content_url does not exist" do
      missing_path =
        Path.join(
          System.tmp_dir!(),
          "media-centarr-test-nonexistent-#{System.unique_integer([:positive])}.mkv"
        )

      refute File.exists?(missing_path)

      params = %{
        action: :play_next,
        entity_id: Ecto.UUID.generate(),
        entity_name: "Ghost Movie",
        content_url: missing_path,
        start_position: 0.0
      }

      assert {:error, :file_not_found} = Sessions.play(params)
    end
  end
end
