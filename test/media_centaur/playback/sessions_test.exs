defmodule MediaCentaur.Playback.SessionsTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Playback.{Entry, Sessions}

  defp for_entity(params, entity_id), do: put_in(params.entry.entity_id, entity_id)

  # A remote player is handed a media URL, which names the file's presence row.
  defp stamped_file(tmp_dir) do
    media_dir = register_media_dir(tmp_dir)
    path = Path.join(media_dir, "Sample.Movie.2010.mkv")
    File.write!(path, "")
    _presence = FilePresence.stamp(path, media_dir)
    path
  end

  describe "play/1" do
    test "returns {:error, :file_not_found} when content_url does not exist" do
      missing_path =
        Path.join(
          System.tmp_dir!(),
          "media-centaur-test-nonexistent-#{System.unique_integer([:positive])}.mkv"
        )

      refute File.exists?(missing_path)

      params = %{
        profile_id: Ecto.UUID.generate(),
        entry: %Entry{
          entity_id: Ecto.UUID.generate(),
          entity_name: "Ghost Movie",
          content_url: missing_path
        }
      }

      assert {:error, :file_not_found} = Sessions.play(params, :host)
    end

    test "a remote player with no channel to this install is offline" do
      path = Path.join(System.tmp_dir!(), "media-centaur-test-#{System.unique_integer([:positive])}.mkv")
      File.write!(path, "")
      on_exit(fn -> File.rm(path) end)

      params = %{
        profile_id: Ecto.UUID.generate(),
        entry: %Entry{entity_id: Ecto.UUID.generate(), entity_name: "Sample Movie", content_url: path}
      }

      assert {:error, :player_offline} = Sessions.play(params, Ecto.UUID.generate())
    end

    @tag :tmp_dir
    test "a remote player with a channel starts a session that loads the file over it", %{
      tmp_dir: tmp_dir
    } do
      path = stamped_file(tmp_dir)

      player_id = Ecto.UUID.generate()
      media_urls = %{for_file: &("http://tv.test/media/" <> &1), presence_id: fn _url -> nil end}
      :ok = MediaCentaur.Playback.Transport.Remote.PlayerRegistry.register(player_id, media_urls)

      params = %{
        profile_id: MediaCentaur.Profiles.owner().id,
        entry: %Entry{entity_id: Ecto.UUID.generate(), entity_name: "Sample Movie", content_url: path}
      }

      assert :ok = Sessions.play(params, player_id)
      assert_receive {:channel, {:attach, session}}
      assert_receive {:channel, {:push, ["loadfile", _url, "replace", -1, _per_file_options]}}
      assert %{player: ^player_id, state: :playing} = Sessions.get(player_id, params.entry.entity_id)

      :ok = Sessions.stop(player_id, params.entry.entity_id)
      refute Process.alive?(session)
    end

    @tag :tmp_dir
    test "a second viewing on a remote player replaces the first: one libmpv, one viewing", %{
      tmp_dir: tmp_dir
    } do
      path = stamped_file(tmp_dir)

      player_id = Ecto.UUID.generate()
      media_urls = %{for_file: &("http://tv.test/media/" <> &1), presence_id: fn _url -> nil end}
      :ok = MediaCentaur.Playback.Transport.Remote.PlayerRegistry.register(player_id, media_urls)

      params = %{
        profile_id: MediaCentaur.Profiles.owner().id,
        entry: %Entry{entity_id: nil, entity_name: "Sample Movie", content_url: path}
      }

      first = Ecto.UUID.generate()
      second = Ecto.UUID.generate()
      assert :ok = Sessions.play(for_entity(params, first), player_id)
      assert_receive {:channel, {:attach, first_session}}

      assert :ok = Sessions.play(for_entity(params, second), player_id)
      assert_receive {:channel, {:attach, _second_session}}
      refute Process.alive?(first_session)
      assert Sessions.get(player_id, first) == nil
      assert %{entity_id: ^second} = Sessions.get(player_id, second)

      :ok = Sessions.stop(player_id, second)
    end

    test "whether a new viewing replaces the player's others is the transport's answer" do
      path = Path.join(System.tmp_dir!(), "media-centaur-test-#{System.unique_integer([:positive])}.mkv")
      File.write!(path, "")
      on_exit(fn -> File.rm(path) end)

      player_id = Ecto.UUID.generate()

      params = %{
        profile_id: MediaCentaur.Profiles.owner().id,
        entry: %Entry{entity_id: nil, entity_name: "Sample Movie", content_url: path}
      }

      holds_many = MediaCentaur.Playback.FakeTransport.new(self(), holds_one_viewing?: false)
      first = Ecto.UUID.generate()
      second = Ecto.UUID.generate()

      assert :ok =
               params |> for_entity(first) |> Map.put(:transport, holds_many) |> Sessions.play(player_id)

      assert :ok =
               params
               |> for_entity(second)
               |> Map.put(:transport, holds_many)
               |> Sessions.play(player_id)

      assert %{entity_id: ^first} = Sessions.get(player_id, first)
      assert %{entity_id: ^second} = Sessions.get(player_id, second)

      holds_one = MediaCentaur.Playback.FakeTransport.new(self(), holds_one_viewing?: true)
      third = Ecto.UUID.generate()

      assert :ok =
               params |> for_entity(third) |> Map.put(:transport, holds_one) |> Sessions.play(player_id)

      assert Sessions.get(player_id, first) == nil
      assert Sessions.get(player_id, second) == nil
      assert %{entity_id: ^third} = Sessions.get(player_id, third)

      :ok = Sessions.stop(player_id, third)
    end
  end
end
