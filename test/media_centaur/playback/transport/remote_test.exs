defmodule MediaCentaur.Playback.Transport.RemoteTest do
  @moduledoc """
  The remote transport with the test process as the player's channel: what
  `open/2` sends, how files are named both ways through the presence row,
  and what a channel going and coming does.
  """

  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Playback.Remote.PlayerRegistry
  alias MediaCentaur.Playback.Transport.Remote

  @base "http://tv.test:2160"

  setup %{tmp_dir: tmp_dir} do
    media_dir = register_media_dir(tmp_dir)
    path = Path.join(media_dir, "Sample.Show.S01E01.mkv")
    File.write!(path, "")
    presence = FilePresence.stamp(path, media_dir)

    locators = %{
      locate: fn presence_id -> "#{@base}/media/#{presence_id}?t=token" end,
      identify: fn url ->
        case URI.parse(url) do
          %URI{path: "/media/" <> id} -> id
          _other -> nil
        end
      end
    }

    player_id = Ecto.UUID.generate()
    :ok = PlayerRegistry.register(player_id, locators)
    %{player_id: player_id, presence: presence, path: path}
  end

  @tag :tmp_dir
  test "a player with no channel is offline; a connected one yields a transport", %{player_id: player_id} do
    assert Remote.new(Ecto.UUID.generate()) == {:error, :player_offline}
    assert {:ok, %Remote{player_id: ^player_id}} = Remote.new(player_id)
  end

  @tag :tmp_dir
  test "open attaches the session and loads the file with the session options as per-file options", %{
    player_id: player_id,
    path: path,
    presence: presence
  } do
    {:ok, transport} = Remote.new(player_id)
    url = Remote.locator(transport, path)
    assert url == "#{@base}/media/#{presence.id}?t=token"

    launch = %{
      session_options: [
        {"keep-open", "yes"},
        {"script-opts-append", "media_centaur_session-profile_id=p1"}
      ],
      content_url: url,
      start_position: 42.5,
      profile_id: "p1"
    }

    assert {[{:attached, :fresh}], transport} = Remote.open(transport, launch)
    assert Remote.attached?(transport)

    me = self()
    assert_received {:channel, {:attach, ^me}}

    # Nothing is set on the player's long-lived instance: every option
    # rides on the file and mpv restores the instance at its end.
    refute_received {:channel, {:push, ["set_property" | _]}}
    refute_received {:channel, {:push, ["change-list" | _]}}

    assert_received {:channel,
                     {:push,
                      [
                        "loadfile",
                        ^url,
                        "replace",
                        -1,
                        "keep-open=%3%yes,script-opts=%35%media_centaur_session-profile_id=p1,start=%4%42.5"
                      ]}}
  end

  @tag :tmp_dir
  test "a successor is queued with the same per-file options, so the chain keeps the viewing's set", %{
    player_id: player_id,
    path: path
  } do
    {:ok, transport} = Remote.new(player_id)
    url = Remote.locator(transport, path)

    launch = %{
      session_options: [{"keep-open", "yes"}],
      content_url: url,
      start_position: 0,
      profile_id: "p1"
    }

    {_events, transport} = Remote.open(transport, launch)

    assert Remote.queue(transport, "#{@base}/media/next?t=token", 300.0) ==
             ["loadfile", "#{@base}/media/next?t=token", "append", -1, "keep-open=%3%yes,start=%5%300.0"]

    refute Remote.draws_subtitles?(transport)
  end

  @tag :tmp_dir
  test "a reattaching open attaches and observes without loading", %{player_id: player_id, path: path} do
    {:ok, transport} = Remote.new(player_id)

    launch = %{
      session_options: [{"keep-open", "yes"}],
      content_url: Remote.locator(transport, path),
      start_position: 100.0,
      profile_id: "p1",
      reattach?: true
    }

    assert {[{:attached, :reconnected}], _transport} = Remote.open(transport, launch)
    me = self()
    assert_received {:channel, {:attach, ^me}}
    refute_received {:channel, {:push, ["loadfile" | _]}}
    refute_received {:channel, {:push, ["set_property" | _]}}
  end

  @tag :tmp_dir
  test "a stop or quit reported by the player ends the viewing; any other end-file does not", %{
    player_id: player_id
  } do
    {:ok, transport} = Remote.new(player_id)
    stopped = %{"event" => "end-file", "reason" => "stop"}
    eof = %{"event" => "end-file", "reason" => "eof"}

    assert {[{:message, ^stopped}, {:closed, {:ok, :ended}}], _transport} =
             Remote.handle_message(transport, {:transport, {:remote, {:message, stopped}}})

    assert {[{:message, ^eof}], _transport} =
             Remote.handle_message(transport, {:transport, {:remote, {:message, eof}}})
  end

  @tag :tmp_dir
  test "identify maps a media URL back to the host path; anything else is nobody's file", %{
    player_id: player_id,
    path: path,
    presence: presence
  } do
    {:ok, transport} = Remote.new(player_id)

    assert Remote.identify(transport, "#{@base}/media/#{presence.id}?t=token") == path
    assert Remote.identify(transport, "#{@base}/media/#{Ecto.UUID.generate()}") == nil
    assert Remote.identify(transport, "/some/local/file.mkv") == nil
  end

  @tag :tmp_dir
  test "a path with no presence row is handed over as it is", %{player_id: player_id} do
    {:ok, transport} = Remote.new(player_id)
    assert Remote.locator(transport, "/nowhere/unknown.mkv") == "/nowhere/unknown.mkv"
  end

  @tag :tmp_dir
  test "a channel going detaches and drops commands; one coming back reattaches", %{player_id: player_id} do
    {:ok, transport} = Remote.new(player_id)

    assert {[{:detached, :closed}], transport} =
             Remote.handle_message(transport, {:transport, {:remote, {:channel_down, :closed}}})

    refute Remote.attached?(transport)
    assert :ok = Remote.send(transport, ["quit"])
    refute_received {:channel, {:push, ["quit"]}}

    me = self()

    assert {[{:attached, :reconnected}], transport} =
             Remote.handle_message(transport, {:transport, {:remote, {:channel_up, me}}})

    assert Remote.attached?(transport)
    assert_received {:channel, {:attach, ^me}}
    assert :ok = Remote.send(transport, ["quit"])
    assert_received {:channel, {:push, ["quit"]}}
  end
end
