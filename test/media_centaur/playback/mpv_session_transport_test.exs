defmodule MediaCentaur.Playback.MpvSessionTransportTest do
  @moduledoc """
  The observer driven through its transport seam: `FakeTransport` stands
  in for the mpv, so the session's reaction to attach, pause, end of file,
  detach and failure is pinned without a process, a socket or a clock.
  """

  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Playback
  alias MediaCentaur.Playback.Events
  alias MediaCentaur.Playback.FakeTransport
  alias MediaCentaur.Playback.SessionRegistry
  alias MediaCentaur.Playback.Sessions
  alias MediaCentaur.Playback.Viewing
  alias MediaCentaur.Profiles

  setup do
    path = Path.join(System.tmp_dir!(), "mc-session-#{System.unique_integer([:positive])}.mkv")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    movie = create_standalone_movie(%{name: "Sample Movie"})

    params = %{
      action: :play,
      entity_id: movie.id,
      profile_id: Profiles.owner().id,
      entity_name: "Sample Movie",
      movie_id: movie.id,
      content_url: path,
      start_position: 0.0,
      transport: FakeTransport.new(self()),
      reattach_window_ms: 100
    }

    Playback.subscribe()

    # A session this test leaves running would show on the next test's
    # Status page as "1 active"; end every session through the public door.
    on_exit(fn ->
      for {{player, entity_id}, _pid} <- SessionRegistry.list(), do: Sessions.stop(player, entity_id)
    end)

    %{params: params, path: path, entity_id: movie.id}
  end

  defp start!(params) do
    :ok = Sessions.play(params, :host)
    pid = SessionRegistry.lookup({:host, params.entity_id})
    assert is_pid(pid)
    pid
  end

  defp attach!(pid) do
    FakeTransport.emit(pid, {:attached, :fresh})
    assert_receive {:mpv_command, ["observe_property", 1, "time-pos"]}
    assert_receive {:playback_state_changed, %Events.PlaybackStateChanged{state: :playing}}
  end

  test "opens the transport with the session options and the located file", %{params: params, path: path} do
    start!(params)

    assert_receive {:transport_opened, launch}
    assert launch.content_url == "fake://" <> path
    assert launch.start_position == 0.0
    assert {"keep-open", "yes"} in launch.session_options
    assert {"resume-playback", "no"} in launch.session_options
    assert Enum.any?(launch.session_options, &match?({"script-opts-append", _}, &1))
  end

  test "attaching observes the properties and broadcasts playing; pause broadcasts paused",
       %{params: params, entity_id: entity_id} do
    pid = start!(params)
    attach!(pid)
    assert_receive {:mpv_command, ["observe_property", 11, "path"]}

    FakeTransport.emit(
      pid,
      {:message, %{"event" => "property-change", "name" => "pause", "data" => true}}
    )

    assert_receive {:playback_state_changed,
                    %Events.PlaybackStateChanged{state: :paused, entity_id: ^entity_id, player: :host}}

    assert %{state: :paused, player: :host} = Sessions.get(:host, entity_id)
  end

  test "end of the playlist quits mpv and ends the session; the transport is closed for good",
       %{params: params, entity_id: entity_id} do
    pid = start!(params)
    attach!(pid)
    ref = Process.monitor(pid)

    FakeTransport.emit(
      pid,
      {:message, %{"event" => "property-change", "name" => "eof-reached", "data" => true}}
    )

    assert_receive {:mpv_command, ["quit"]}
    assert_receive {:playback_state_changed, %Events.PlaybackStateChanged{state: :stopped}}
    assert_receive {:session_ended, %Events.SessionEnded{entity_id: ^entity_id, player: :host}}

    FakeTransport.emit(pid, {:closed, {:ok, :ended}})
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert_receive {:transport_closed, true}
    assert Sessions.get(:host, entity_id) == nil
  end

  test "a detached transport that comes back is re-observed; nothing ends", %{params: params} do
    pid = start!(params)
    attach!(pid)

    FakeTransport.emit(pid, {:detached, :channel_lost})
    refute_receive {:playback_state_changed, %Events.PlaybackStateChanged{state: :stopped}}, 50

    FakeTransport.emit(pid, {:attached, :reconnected})
    assert_receive {:mpv_command, ["observe_property", 1, "time-pos"]}
    assert Process.alive?(pid)
  end

  test "a detached transport that stays away past the window ends the session",
       %{params: params, entity_id: entity_id} do
    pid = start!(params)
    attach!(pid)
    ref = Process.monitor(pid)

    FakeTransport.emit(pid, {:detached, :channel_lost})

    assert_receive {:playback_state_changed, %Events.PlaybackStateChanged{state: :stopped}}, 500
    assert_receive {:session_ended, %Events.SessionEnded{entity_id: ^entity_id}}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  test "a deliberate stop quits the player and ends the session", %{params: params, entity_id: entity_id} do
    pid = start!(params)
    attach!(pid)
    ref = Process.monitor(pid)

    :ok = Sessions.stop(:host, entity_id)

    assert_receive {:mpv_command, ["quit"]}
    assert_receive {:playback_state_changed, %Events.PlaybackStateChanged{state: :stopped}}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert_receive {:transport_closed, false}
  end

  test "a file the transport cannot name to the player fails the viewing before anything loads", %{
    params: params,
    entity_id: entity_id
  } do
    :ok = Sessions.play(%{params | transport: FakeTransport.new(self(), locates?: false)}, :host)

    assert_receive {:playback_failed,
                    %Events.PlaybackFailed{entity_id: ^entity_id, reason: :file_unknown, payload: %{message: message}}}

    assert message =~ "indexed"
    refute_received {:transport_opened, _launch}
    assert_receive {:transport_closed, true}
  end

  test "a transport that fails to start broadcasts the failure and ends", %{
    params: params,
    entity_id: entity_id
  } do
    pid = start!(params)
    ref = Process.monitor(pid)

    FakeTransport.emit(pid, {:closed, {:error, :startup_failure, "mpv exited before playback started"}})

    assert_receive {:playback_failed,
                    %Events.PlaybackFailed{entity_id: ^entity_id, reason: :startup_failure}}

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  describe "a reader's commands" do
    test "are rendered to IPC by the session and sent through its transport", %{
      params: params,
      entity_id: entity_id
    } do
      pid = start!(params)
      attach!(pid)

      assert Playback.command(:host, entity_id, :toggle_pause) == :ok
      assert_receive {:mpv_command, ["cycle", "pause"]}

      assert Playback.command(:host, entity_id, {:seek, -10}) == :ok
      assert_receive {:mpv_command, ["seek", -10, "relative"]}

      assert Playback.command(:host, entity_id, {:select_track, :subtitle, :none}) == :ok
      assert_receive {:mpv_command, ["set_property", "sid", "no"]}

      # No prompt shows, so activating one does nothing.
      assert Playback.command(:host, entity_id, :activate_prompt) == :ok
      refute_receive {:mpv_command, ["playlist-next"]}, 50
      refute_receive {:mpv_command, ["seek", _, "absolute"]}, 50
    end

    test "a seek never crosses the end: it stops short, then there is nothing to send", %{
      params: params,
      entity_id: entity_id
    } do
      pid = start!(params)
      attach!(pid)

      FakeTransport.emit(
        pid,
        {:message, %{"event" => "property-change", "name" => "duration", "data" => 90.0}}
      )

      FakeTransport.emit(
        pid,
        {:message, %{"event" => "property-change", "name" => "time-pos", "data" => 85.0}}
      )

      assert Playback.command(:host, entity_id, {:seek, 30}) == :ok
      assert_receive {:mpv_command, ["seek", 89.0, "absolute+exact"]}

      FakeTransport.emit(
        pid,
        {:message, %{"event" => "property-change", "name" => "time-pos", "data" => 89.5}}
      )

      assert Playback.command(:host, entity_id, {:seek, 30}) == :ok
      refute_receive {:mpv_command, ["seek", _, "relative"]}, 50
    end

    test "a command for a viewing that does not exist is refused", %{entity_id: entity_id} do
      assert Playback.command(:host, entity_id, :toggle_pause) == {:error, :no_session}
    end
  end

  describe "the viewing stream" do
    test "carries the viewing on attach, on every discrete change, and on position once a second; ends with the session",
         %{params: params, entity_id: entity_id} do
      Playback.subscribe_viewing(:host)
      pid = start!(params)
      attach!(pid)
      assert_receive {:viewing, %Viewing{entity_id: ^entity_id, player: :host, state: :playing}}

      FakeTransport.emit(
        pid,
        {:message, %{"event" => "property-change", "name" => "pause", "data" => true}}
      )

      assert_receive {:viewing, %Viewing{state: :paused}}

      FakeTransport.emit(
        pid,
        {:message, %{"event" => "property-change", "name" => "sub-text", "data" => "A line"}}
      )

      assert_receive {:viewing, %Viewing{subtitle_text: "A line"}}

      FakeTransport.emit(pid, {:message, %{"event" => "property-change", "name" => "sub-text"}})
      assert_receive {:viewing, %Viewing{subtitle_text: nil}}

      FakeTransport.emit(
        pid,
        {:message, %{"event" => "property-change", "name" => "chapter", "data" => 1}}
      )

      assert_receive {:viewing, %Viewing{chapter: 1}}

      FakeTransport.emit(
        pid,
        {:message, %{"event" => "property-change", "name" => "time-pos", "data" => 1.0}}
      )

      FakeTransport.emit(
        pid,
        {:message, %{"event" => "property-change", "name" => "time-pos", "data" => 1.5}}
      )

      assert_receive {:viewing, %Viewing{position_seconds: 1.0}}
      refute_receive {:viewing, %Viewing{position_seconds: 1.5}}, 50

      Sessions.stop(:host, entity_id)
      assert_receive {:viewing_ended, %Events.ViewingEnded{entity_id: ^entity_id, player: :host}}
    end
  end

  describe "a player that draws no subtitles" do
    test "never has a bitmap track enforced; a file with only bitmap tracks gets subtitles off",
         %{params: params} do
      params = %{params | transport: FakeTransport.new(self(), draws_subtitles?: false)}
      pid = start!(params)
      attach!(pid)

      tracks = [
        %{"id" => 1, "type" => "audio", "lang" => "eng", "codec" => "dts"},
        %{"id" => 1, "type" => "sub", "lang" => "eng", "codec" => "hdmv_pgs_subtitle"}
      ]

      FakeTransport.emit(
        pid,
        {:message, %{"event" => "property-change", "name" => "track-list", "data" => tracks}}
      )

      assert_receive {:mpv_command, ["set_property", "sid", "no"]}
      refute_receive {:mpv_command, ["set_property", "sid", 1]}, 50
    end
  end
end
