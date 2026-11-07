defmodule MediaCentaurWeb.PlayerSocketTest do
  @moduledoc """
  The socket as the gate's enforcement point for the player channel
  (ADR-079): the test process is the socket, opened through `init/1`, and
  answers the recovery question the open asks.
  """

  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.Players
  alias MediaCentaur.Players.Events.PlayerRemoved
  alias MediaCentaurWeb.PlayerSocket

  @media_urls %{for_file: &Function.identity/1, presence_id: &Function.identity/1}

  # A channel no session holds is asked what it plays; this player plays nothing.
  defp answer_recovery do
    assert_receive {:channel, {:request, from, ref, ["get_property", "path"]}}
    send(from, {ref, %{"error" => "property unavailable"}})
    await_supervised_tasks()
  end

  defp opening(player_id, device \\ nil),
    do: %{player_id: player_id, media_urls: @media_urls, address: "192.168.1.40", device: device}

  test "the channel's opening and closing are when the host last saw the player, from where, as what" do
    player = create_player()
    {:ok, state} = PlayerSocket.init(opening(player.id, %{"model" => "Sample TV 4K"}))
    answer_recovery()

    opened = Players.get(player.id)
    assert opened.last_address == "192.168.1.40"
    assert opened.device.model == "Sample TV 4K"
    assert %DateTime{} = opened.last_seen_at

    PlayerSocket.terminate(:remote, state)
    assert DateTime.after?(Players.get(player.id).last_seen_at, opened.last_seen_at)
  end

  test "its own player's removal stops the device's mpv and closes the channel; another player's removal is nobody's" do
    player_id = Ecto.UUID.generate()
    {:ok, state} = PlayerSocket.init(opening(player_id))
    answer_recovery()

    Players.Events.broadcast(%PlayerRemoved{id: Ecto.UUID.generate()})
    assert_receive {:player_removed, %PlayerRemoved{}} = another
    assert {:ok, ^state} = PlayerSocket.handle_info(another, state)

    {:ok, state} = PlayerSocket.handle_info({:channel, {:attach, self()}}, state)
    Players.Events.broadcast(%PlayerRemoved{id: player_id})
    assert_receive {:player_removed, %PlayerRemoved{id: ^player_id}} = own

    assert {:stop, {:shutdown, :removed}, {1000, "removed"}, [{:text, frame}], %{session: nil}} =
             PlayerSocket.handle_info(own, state)

    assert Jason.decode!(frame) == %{"command" => ["stop"]}
    assert_received {:transport, {:remote, {:channel_down, {:shutdown, :removed}}}}
  end
end
