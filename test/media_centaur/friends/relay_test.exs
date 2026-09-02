defmodule MediaCentaur.Friends.RelayTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Events.RelayAdded
  alias MediaCentaur.Friends.Events.RelayRemoved
  alias MediaCentaur.Friends.Relay

  describe "add_relay/1" do
    test "stores a ws/wss URL, normalized, and broadcasts" do
      Friends.subscribe()
      assert {:ok, %Relay{url: "wss://relay.example/"}} = Friends.add_relay("wss://relay.example/")
      assert_receive {:relay_added, %RelayAdded{url: "wss://relay.example/"}}, 500
      assert {:ok, %Relay{url: "ws://127.0.0.1:7777/"}} = Friends.add_relay("  ws://127.0.0.1:7777  ")

      assert [%Relay{url: "ws://127.0.0.1:7777/"}, %Relay{url: "wss://relay.example/"}] =
               Friends.list_relays()
    end

    test "is idempotent on the same URL" do
      {:ok, first} = Friends.add_relay("wss://relay.example")
      {:ok, second} = Friends.add_relay("wss://relay.example/")
      assert first.id == second.id
      assert length(Friends.list_relays()) == 1
    end

    test "rejects non-websocket or hostless URLs" do
      for bad <- ["https://relay.example", "relay.example", "wss://", "wss://user:pw@relay.example", ""] do
        assert {:error, %Ecto.Changeset{}} = Friends.add_relay(bad), bad
      end
    end
  end

  describe "normalize/1" do
    test "lowercases the scheme and the host" do
      assert Relay.normalize("WSS://Relay.Example") == "wss://relay.example/"
      assert Relay.normalize("  WS://LOCALHOST:7777/Inbox  ") == "ws://localhost:7777/Inbox"
    end

    test "returns the input trimmed when it does not parse as a relay URL" do
      assert Relay.normalize("  relay.example  ") == "relay.example"
    end
  end

  describe "remove_relay/1" do
    test "removes by URL and broadcasts; absent is a no-op" do
      {:ok, _relay} = Friends.add_relay("wss://relay.example")
      Friends.subscribe()
      assert :ok = Friends.remove_relay("wss://relay.example/")
      assert_receive {:relay_removed, %RelayRemoved{url: "wss://relay.example/"}}, 500
      assert Friends.list_relays() == []
      assert :ok = Friends.remove_relay("wss://relay.example/")
      refute_receive {:relay_removed, _event}, 100
    end
  end
end
