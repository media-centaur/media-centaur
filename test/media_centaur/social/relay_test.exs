defmodule MediaCentaur.Social.RelayTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Events.RelayAdded
  alias MediaCentaur.Social.Events.RelayRemoved
  alias MediaCentaur.Social.Relay

  describe "add_relay/1" do
    test "stores a ws/wss URL, normalized, and broadcasts" do
      Social.subscribe()
      assert {:ok, %Relay{url: "wss://relay.example/"}} = Social.add_relay("wss://relay.example/")
      assert_receive {:relay_added, %RelayAdded{url: "wss://relay.example/"}}, 500
      assert {:ok, %Relay{url: "ws://127.0.0.1:7777/"}} = Social.add_relay("  ws://127.0.0.1:7777  ")

      assert [%Relay{url: "ws://127.0.0.1:7777/"}, %Relay{url: "wss://relay.example/"}] =
               Social.list_relays()
    end

    test "is idempotent on the same URL" do
      {:ok, first} = Social.add_relay("wss://relay.example")
      {:ok, second} = Social.add_relay("wss://relay.example/")
      assert first.id == second.id
      assert length(Social.list_relays()) == 1
    end

    test "rejects non-websocket or hostless URLs" do
      for bad <- ["https://relay.example", "relay.example", "wss://", "wss://user:pw@relay.example", ""] do
        assert {:error, %Ecto.Changeset{}} = Social.add_relay(bad), bad
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
      {:ok, _relay} = Social.add_relay("wss://relay.example")
      Social.subscribe()
      assert :ok = Social.remove_relay("wss://relay.example/")
      assert_receive {:relay_removed, %RelayRemoved{url: "wss://relay.example/"}}, 500
      assert Social.list_relays() == []
      assert :ok = Social.remove_relay("wss://relay.example/")
      refute_receive {:relay_removed, _event}, 100
    end
  end
end
