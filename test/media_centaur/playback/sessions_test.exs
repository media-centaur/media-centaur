defmodule MediaCentaur.Playback.SessionsTest do
  use MediaCentaur.DataCase, async: false

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

    test "a remote player with a channel starts a session that loads the file over it" do
      path = Path.join(System.tmp_dir!(), "media-centaur-test-#{System.unique_integer([:positive])}.mkv")
      File.write!(path, "")
      on_exit(fn -> File.rm(path) end)

      player_id = Ecto.UUID.generate()
      locators = %{locate: &("http://tv.test/media/" <> &1), identify: fn _url -> nil end}
      :ok = MediaCentaur.Playback.Remote.PlayerRegistry.register(player_id, locators)

      params = %{
        action: :play,
        entity_id: Ecto.UUID.generate(),
        profile_id: MediaCentaur.Profiles.owner().id,
        entity_name: "Sample Movie",
        content_url: path,
        start_position: 0.0
      }

      assert :ok = Sessions.play(params, player_id)
      assert_receive {:channel, {:attach, session}}
      assert_receive {:channel, {:push, ["loadfile", _url, "replace"]}}
      assert %{player: ^player_id, state: :playing} = Sessions.get(player_id, params.entity_id)

      :ok = Sessions.stop(player_id, params.entity_id)
      refute Process.alive?(session)
    end
  end
end
