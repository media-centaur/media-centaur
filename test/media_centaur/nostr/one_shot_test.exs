defmodule MediaCentaur.Nostr.OneShotTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.FakeRelay
  alias MediaCentaur.Nostr.Filter
  alias MediaCentaur.Nostr.OneShot

  @secret_hex String.duplicate("0", 63) <> "3"

  defp secret, do: MediaCentaur.Secret.wrap(@secret_hex)
  defp signer, do: fn %Event{} = event -> Event.sign(event, secret()) end

  defp signed(content, kind \\ 1) do
    Event.sign(
      Event.new(%{created_at: System.os_time(:second), kind: kind, tags: [], content: content}),
      secret()
    )
  end

  describe "publish/4" do
    test "returns :ok once the relay accepts the event" do
      relay = FakeRelay.start()
      event = signed("hello")

      assert :ok = OneShot.publish(relay.url, event, signer())
      assert_received {:relay_in, ["EVENT", %{"content" => "hello"}]}
    end

    test "answers the AUTH challenge before publishing" do
      relay = FakeRelay.start(auth: true)
      event = signed("hello")

      assert :ok = OneShot.publish(relay.url, event, signer())
      assert_received {:relay_in, ["AUTH", %{"kind" => 22_242}]}
      assert_received {:relay_in, ["EVENT", %{"content" => "hello"}]}
    end

    test "returns the relay's reason when the event is refused" do
      relay =
        FakeRelay.start(accept: false, reason: "restricted: this key is not a member of this relay")

      assert {:error, "restricted: this key is not a member of this relay"} =
               OneShot.publish(relay.url, signed("hello"), signer())
    end

    test "returns an error when the relay is unreachable" do
      assert {:error, {:disconnected, _reason}} =
               OneShot.publish("ws://127.0.0.1:1/", signed("hello"), signer())
    end
  end

  describe "query/4" do
    test "returns the stored events matching the filters" do
      relay = FakeRelay.start(auth: true, events: [signed("kept", 32_160), signed("other", 1)])

      assert {:ok, [%Event{content: "kept"}]} =
               OneShot.query(relay.url, [Filter.new(kinds: [32_160])], signer())
    end

    test "returns an empty list when nothing matches" do
      relay = FakeRelay.start()

      assert {:ok, []} = OneShot.query(relay.url, [Filter.new(kinds: [32_160])], signer())
    end
  end
end
