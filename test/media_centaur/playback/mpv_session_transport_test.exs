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
    %{params: params, path: path, entity_id: movie.id}
  end

  defp start!(params) do
    :ok = Sessions.play(params)
    pid = SessionRegistry.lookup(params.entity_id)
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
                    %Events.PlaybackStateChanged{state: :paused, entity_id: ^entity_id}}

    assert %{state: :paused} = Sessions.get(entity_id)
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
    assert_receive {:session_ended, %Events.SessionEnded{entity_id: ^entity_id}}

    FakeTransport.emit(pid, {:closed, {:ok, :ended}})
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert_receive {:transport_closed, true}
    assert Sessions.get(entity_id) == nil
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
end
