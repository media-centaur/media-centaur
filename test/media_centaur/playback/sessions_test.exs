defmodule MediaCentaur.Playback.SessionsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.Sessions

  describe "play/1" do
    test "returns {:error, :file_not_found} when content_url does not exist" do
      missing_path =
        Path.join(
          System.tmp_dir!(),
          "media-centaur-test-nonexistent-#{System.unique_integer([:positive])}.mkv"
        )

      refute File.exists?(missing_path)

      params = %{
        action: :play_next,
        entity_id: Ecto.UUID.generate(),
        profile_id: Ecto.UUID.generate(),
        entity_name: "Ghost Movie",
        content_url: missing_path,
        start_position: 0.0
      }

      assert {:error, :file_not_found} = Sessions.play(params, :host)
    end

    test "a remote player with no channel to this install is offline" do
      path = Path.join(System.tmp_dir!(), "media-centaur-test-#{System.unique_integer([:positive])}.mkv")
      File.write!(path, "")
      on_exit(fn -> File.rm(path) end)

      params = %{
        action: :play,
        entity_id: Ecto.UUID.generate(),
        profile_id: Ecto.UUID.generate(),
        entity_name: "Sample Movie",
        content_url: path,
        start_position: 0.0
      }

      assert {:error, :player_offline} = Sessions.play(params, Ecto.UUID.generate())
    end
  end
end
