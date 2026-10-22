defmodule MediaCentaur.Playback.Remote.ChannelTest do
  @moduledoc """
  The channel protocol over the handler's state, with the test process as
  the WebSocket owner: what a frame in does, what a message to the handler
  pushes, how requests correlate, and when liveness closes the channel.
  """

  use MediaCentaur.Case, async: false

  alias MediaCentaur.Players
  alias MediaCentaur.Players.Events.PlayerRemoved
  alias MediaCentaur.Playback.Remote.Channel
  alias MediaCentaur.Playback.Remote.PlayerRegistry

  @locators %{locate: &Function.identity/1, identify: &Function.identity/1}

  defp player_id, do: Ecto.UUID.generate()

  defp connected(player_id \\ player_id()) do
    {:ok, state} = Channel.connect(player_id, @locators)
    state
  end

  test "connect registers the caller as the player's channel; a second channel must evict the first" do
    player_id = player_id()
    _state = connected(player_id)
    assert {pid, locators} = PlayerRegistry.lookup(player_id)
    assert pid == self()
    assert locators == @locators
    assert player_id in PlayerRegistry.connected()

    other = Task.async(fn -> Channel.connect(player_id, @locators) end)
    assert {:error, {:already_registered, pid}} = Task.await(other)
    assert pid == self()
  end

  test "replace closes the older channel and waits for it to go" do
    player_id = player_id()

    older =
      spawn(fn ->
        {:ok, state} = Channel.connect(player_id, @locators)

        receive do
          message ->
            assert {:stop, {:shutdown, :replaced}, _state} = Channel.handle_message(state, message)
        end
      end)

    # The older process must have registered before the replacement.
    assert_eventually(fn -> match?({^older, _}, PlayerRegistry.lookup(player_id)) end)

    assert :ok = Channel.replace(older)
    refute Process.alive?(older)
  end

  test "an mpv object from the player reaches the attached session; none is dropped silently" do
    state = connected()
    object = %{"event" => "property-change", "name" => "pause", "data" => true}

    assert {:ok, state} = Channel.frame_in(state, Jason.encode!(object))
    refute_received {:transport, _}

    {:ok, state} = Channel.handle_message(state, {:channel, {:attach, self()}})
    assert {:ok, _state} = Channel.frame_in(state, Jason.encode!(object))
    assert_received {:transport, {:remote, {:message, ^object}}}
  end

  test "a reply correlates to the request that asked for it" do
    state = connected()
    channel = self()

    requester = Task.async(fn -> Channel.request(channel, ["get_property", "path"], 1_000) end)

    assert_receive {:channel, {:request, _from, _ref, ["get_property", "path"]}} = message
    assert {:push, {:text, json}, state} = Channel.handle_message(state, message)
    assert %{"command" => ["get_property", "path"], "request_id" => 1} = Jason.decode!(json)

    reply = %{"request_id" => 1, "error" => "success", "data" => "/media/x"}
    assert {:ok, _state} = Channel.frame_in(state, Jason.encode!(reply))
    assert Task.await(requester) == {:ok, reply}
  end

  test "a request nobody answers times out" do
    channel = self()
    assert Channel.request(channel, ["get_property", "path"], 50) == {:error, :timeout}
  end

  test "push encodes one IPC command as one text frame" do
    state = connected()
    assert {:push, {:text, json}, _state} = Channel.handle_message(state, {:channel, {:push, ["quit"]}})
    assert Jason.decode!(json) == %{"command" => ["quit"]}
  end

  test "a malformed frame closes the channel" do
    state = connected()
    assert {:stop, :malformed_frame, _state} = Channel.frame_in(state, "not json")
    assert {:stop, :malformed_frame, _state} = Channel.frame_in(state, "[1, 2]")
  end

  test "ping while pongs are fresh; close once a pong is overdue" do
    state = connected()
    assert {:push, {:ping, ""}, state} = Channel.handle_message(state, {:channel, :ping})

    stale = %{state | last_pong_at: state.last_pong_at - Channel.pong_grace_ms() - 1}
    assert {:stop, :pong_overdue, _state} = Channel.handle_message(stale, {:channel, :ping})

    assert {:push, {:ping, ""}, _state} = Channel.handle_message(Channel.pong(stale), {:channel, :ping})
  end

  test "a removed player's channel tells the device's mpv to stop and closes; another player's removal is nobody's" do
    player_id = player_id()
    state = connected(player_id)

    Players.Events.broadcast(%PlayerRemoved{id: Ecto.UUID.generate()})
    assert_receive {:player_removed, %PlayerRemoved{}} = another
    assert Channel.handle_message(state, another) == :unhandled

    {:ok, state} = Channel.handle_message(state, {:channel, {:attach, self()}})
    Players.Events.broadcast(%PlayerRemoved{id: player_id})
    assert_receive {:player_removed, %PlayerRemoved{id: ^player_id}} = own

    assert {:stop, {:shutdown, :removed}, {1000, "removed"}, [{:text, frame}], %{session: nil}} =
             Channel.handle_message(state, own)

    assert Jason.decode!(frame) == %{"command" => ["stop"]}
    assert_received {:transport, {:remote, {:channel_down, {:shutdown, :removed}}}}
  end

  test "closing tells the attached session its channel is down" do
    state = connected()
    assert :ok = Channel.closed(state, :remote)
    refute_received {:transport, _}

    {:ok, state} = Channel.handle_message(state, {:channel, {:attach, self()}})
    assert :ok = Channel.closed(state, :remote)
    assert_received {:transport, {:remote, {:channel_down, :remote}}}
  end

  defp assert_eventually(predicate, attempts \\ 50) do
    cond do
      predicate.() -> :ok
      attempts == 0 -> flunk("condition never held")
      true -> Process.sleep(10) && assert_eventually(predicate, attempts - 1)
    end
  end
end
