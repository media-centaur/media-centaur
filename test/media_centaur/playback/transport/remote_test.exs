defmodule MediaCentaur.Playback.Transport.RemoteTest do
  @moduledoc """
  The remote transport with the test process as the player's channel: what
  `open/2` sends, how files are named both ways through the presence row,
  and what a channel going and coming does.
  """

  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.FilePresence
  alias MediaCentaur.Subtitles
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
      locate_subtitle: fn presence_id, basename ->
        "#{@base}/media/#{presence_id}/subtitles/#{basename}?t=token"
      end,
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

  defp locate(transport, path) do
    {:ok, url} = Remote.locator(transport, path)
    url
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
    {:ok, url} = Remote.locator(transport, path)
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
    # rides on the file and mpv restores the instance at its end. The
    # stream's own options lead: FFmpeg resumes the HTTP range after a
    # dropped connection instead of taking the short read for the end.
    refute_received {:channel, {:push, ["set_property" | _]}}
    refute_received {:channel, {:push, ["change-list" | _]}}

    assert_received {:channel,
                     {:push,
                      [
                        "loadfile",
                        ^url,
                        "replace",
                        -1,
                        "stream-lavf-o=%40%reconnect=1,reconnect_on_network_error=1,keep-open=%3%yes,script-opts=%35%media_centaur_session-profile_id=p1,start=%4%42.5"
                      ]}}
  end

  @tag :tmp_dir
  test "a successor is queued with the same per-file options, so the chain keeps the viewing's set", %{
    player_id: player_id,
    path: path
  } do
    {:ok, transport} = Remote.new(player_id)
    {:ok, url} = Remote.locator(transport, path)

    launch = %{
      session_options: [{"keep-open", "yes"}],
      content_url: url,
      start_position: 0,
      profile_id: "p1"
    }

    {_events, transport} = Remote.open(transport, launch)

    assert Remote.queue(transport, "#{@base}/media/next?t=token", 300.0) ==
             [
               "loadfile",
               "#{@base}/media/next?t=token",
               "append",
               -1,
               "stream-lavf-o=%40%reconnect=1,reconnect_on_network_error=1,keep-open=%3%yes,start=%5%300.0"
             ]

    refute Remote.draws_subtitles?(transport)
  end

  @tag :tmp_dir
  test "a reattaching open attaches and observes without loading", %{player_id: player_id, path: path} do
    {:ok, transport} = Remote.new(player_id)

    launch = %{
      session_options: [{"keep-open", "yes"}],
      content_url: locate(transport, path),
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
  test "an end-file before the session's own file starts is the replaced file's and is dropped", %{
    player_id: player_id,
    path: path
  } do
    {:ok, transport} = Remote.new(player_id)

    launch = %{
      session_options: [],
      content_url: locate(transport, path),
      start_position: 0,
      profile_id: "p1"
    }

    {_events, transport} = Remote.open(transport, launch)

    # mpv ends the file it was playing before it starts ours; the bridge
    # cannot know the reason, and whatever it says, it is not our end.
    stale = {:transport, {:remote, {:message, %{"event" => "end-file", "reason" => "eof"}}}}
    assert {[], transport} = Remote.handle_message(transport, stale)
    stale_stop = {:transport, {:remote, {:message, %{"event" => "end-file", "reason" => "stop"}}}}
    assert {[], transport} = Remote.handle_message(transport, stale_stop)

    started = {:transport, {:remote, {:message, %{"event" => "start-file"}}}}

    assert {[{:message, %{"event" => "start-file"}}], transport} =
             Remote.handle_message(transport, started)

    ours = {:transport, {:remote, {:message, %{"event" => "end-file", "reason" => "stop"}}}}

    assert {[{:message, _}, {:closed, {:ok, :ended}}], _transport} =
             Remote.handle_message(transport, ours)
  end

  @tag :tmp_dir
  test "a reattaching session's file has already started: its first end-file counts", %{
    player_id: player_id,
    path: path
  } do
    {:ok, transport} = Remote.new(player_id)

    launch = %{
      session_options: [],
      content_url: locate(transport, path),
      start_position: 0,
      profile_id: "p1",
      reattach?: true
    }

    {_events, transport} = Remote.open(transport, launch)
    ours = {:transport, {:remote, {:message, %{"event" => "end-file", "reason" => "stop"}}}}

    assert {[{:message, _}, {:closed, {:ok, :ended}}], _transport} =
             Remote.handle_message(transport, ours)
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
  test "a path with no presence row cannot be named to the player", %{player_id: player_id} do
    {:ok, transport} = Remote.new(player_id)
    assert Remote.locator(transport, "/nowhere/unknown.mkv") == {:error, :no_presence}
  end

  @tag :tmp_dir
  test "once mpv reports the file loaded, the file's sidecars are added as external tracks, titled and tagged",
       %{
         player_id: player_id,
         path: path,
         presence: presence
       } do
    watched_file =
      create_linked_file(%{
        file_path: path,
        media_dir: Path.dirname(path),
        movie_id: create_standalone_movie().id
      })

    for {name, language} <- [{"Sample.Show.S01E01.en.srt", "en"}, {"Sample.Show.S01E01.srt", nil}] do
      {:ok, _track} =
        Subtitles.create_track(%{
          watched_file_id: watched_file.id,
          kind: :sidecar,
          language: language,
          source: Path.join(Path.dirname(path), name)
        })
    end

    {:ok, transport} = Remote.new(player_id)
    url = "#{@base}/media/#{presence.id}?t=token"
    reported = %{"event" => "property-change", "name" => "path", "data" => url}
    loaded = %{"event" => "file-loaded"}

    # The path names the file; file-loaded is when mpv takes external tracks for it.
    assert {[{:message, ^reported}], transport} =
             Remote.handle_message(transport, {:transport, {:remote, {:message, reported}}})

    refute_received {:channel, {:push, ["sub-add" | _]}}

    assert {[{:message, ^loaded}], _transport} =
             Remote.handle_message(transport, {:transport, {:remote, {:message, loaded}}})

    english = "#{@base}/media/#{presence.id}/subtitles/Sample.Show.S01E01.en.srt?t=token"
    untagged = "#{@base}/media/#{presence.id}/subtitles/Sample.Show.S01E01.srt?t=token"
    assert_received {:channel, {:push, ["sub-add", ^english, "auto", "Sample.Show.S01E01.en.srt", "en"]}}
    assert_received {:channel, {:push, ["sub-add", ^untagged, "auto", "Sample.Show.S01E01.srt"]}}
  end

  @tag :tmp_dir
  test "mpv reports file-loaded and the path in either order: the sidecars are added once both are known, once per file",
       %{
         player_id: player_id,
         path: path,
         presence: presence
       } do
    watched_file =
      create_linked_file(%{
        file_path: path,
        media_dir: Path.dirname(path),
        movie_id: create_standalone_movie().id
      })

    {:ok, _track} =
      Subtitles.create_track(%{
        watched_file_id: watched_file.id,
        kind: :sidecar,
        language: "en",
        source: Path.join(Path.dirname(path), "Sample.Show.S01E01.en.srt")
      })

    {:ok, transport} = Remote.new(player_id)
    url = "#{@base}/media/#{presence.id}?t=token"
    reported = %{"event" => "property-change", "name" => "path", "data" => url}
    loaded = %{"event" => "file-loaded"}
    started = %{"event" => "start-file"}
    english = "#{@base}/media/#{presence.id}/subtitles/Sample.Show.S01E01.en.srt?t=token"

    message = fn transport, object ->
      Remote.handle_message(transport, {:transport, {:remote, {:message, object}}})
    end

    # file-loaded first (seen on the Sony): nothing to look up yet.
    {[{:message, ^loaded}], transport} = message.(transport, loaded)
    refute_received {:channel, {:push, ["sub-add" | _]}}

    # The path arrives: the file is known and loaded.
    {[{:message, ^reported}], transport} = message.(transport, reported)
    assert_received {:channel, {:push, ["sub-add", ^english, "auto", "Sample.Show.S01E01.en.srt", "en"]}}

    # A second report of the same path adds nothing again.
    {[{:message, ^reported}], transport} = message.(transport, reported)
    refute_received {:channel, {:push, ["sub-add" | _]}}

    # The next file starts: the previous one is forgotten, so its loaded report alone adds nothing.
    {[{:message, ^started}], transport} = message.(transport, started)
    {[{:message, ^loaded}], _transport} = message.(transport, loaded)
    refute_received {:channel, {:push, ["sub-add" | _]}}
  end

  @tag :tmp_dir
  test "a removed player's channel ends the viewing at once: the player is not coming back", %{
    player_id: player_id
  } do
    {:ok, transport} = Remote.new(player_id)

    assert {[{:closed, {:ok, :ended}}], %{channel: nil}} =
             Remote.handle_message(
               transport,
               {:transport, {:remote, {:channel_down, {:shutdown, :removed}}}}
             )
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
