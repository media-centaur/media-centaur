defmodule MediaCentaur.Nostr.ConnectionTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.Connection
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.FakeRelay
  alias MediaCentaur.Nostr.Filter

  @secret_hex String.duplicate("0", 63) <> "3"

  defp secret, do: MediaCentaur.Secret.wrap(@secret_hex)
  defp signer, do: fn %Event{} = event -> Event.sign(event, secret()) end

  defp start_connection(relay, opts \\ []) do
    ExUnit.Callbacks.start_supervised!(
      {Connection, [url: relay.url, owner: self(), signer: signer()] ++ opts},
      id: :"conn_#{System.unique_integer([:positive])}"
    )
  end

  defp signed(content, kind \\ 1) do
    Event.sign(
      Event.new(%{created_at: System.os_time(:second), kind: kind, tags: [], content: content}),
      secret()
    )
  end

  test "connects and reports :connected; status reflects it" do
    relay = FakeRelay.start()
    conn = start_connection(relay)
    url = relay.url

    assert_receive {:nostr, ^url, :connected}, 2_000
    assert Connection.status(conn) == :connected
  end

  test "publishes an event and relays the OK verdict" do
    relay = FakeRelay.start()
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    event = signed("hello")
    :ok = Connection.publish(conn, event)
    id = event.id

    assert_receive {:relay_in, ["EVENT", %{"id" => ^id}]}, 2_000
    assert_receive {:nostr, ^url, {:ok, ^id, true, ""}}, 2_000
  end

  test "reports a rejected publish" do
    relay = FakeRelay.start(accept: false, reason: "blocked: not on the allowlist")
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    event = signed("hello")
    :ok = Connection.publish(conn, event)
    id = event.id
    assert_receive {:nostr, ^url, {:ok, ^id, false, "blocked: not on the allowlist"}}, 2_000
  end

  test "subscribes, receives stored events, then EOSE; live pushes arrive too" do
    stored = signed("stored", 32_160)
    relay = FakeRelay.start(events: [stored])
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    :ok = Connection.subscribe(conn, "feed", [Filter.new(kinds: [32_160])])
    assert_receive {:relay_in, ["REQ", "feed", %{"kinds" => [32_160]}]}, 2_000
    assert_receive {:nostr, ^url, {:event, "feed", %Event{content: "stored"}}}, 2_000
    assert_receive {:nostr, ^url, {:eose, "feed"}}, 2_000

    live = signed("live", 32_160)
    FakeRelay.push(relay, ["EVENT", "feed", Event.to_map(live)])
    assert_receive {:nostr, ^url, {:event, "feed", %Event{content: "live"}}}, 2_000

    :ok = Connection.unsubscribe(conn, "feed")
    assert_receive {:relay_in, ["CLOSE", "feed"]}, 2_000
  end

  test "answers an AUTH challenge with a signed kind-22242 event and then subscribes" do
    relay = FakeRelay.start(auth: true)
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    assert_receive {:relay_in, ["AUTH", %{"kind" => 22_242, "tags" => tags}]}, 2_000
    assert ["relay", ^url] = Enum.find(tags, &(hd(&1) == "relay"))
    assert Enum.any?(tags, &(hd(&1) == "challenge"))
    assert_receive {:nostr, ^url, {:auth, :ok}}, 2_000

    :ok = Connection.subscribe(conn, "s", [Filter.new(kinds: [1])])
    assert_receive {:nostr, ^url, {:eose, "s"}}, 2_000
  end

  test "reconnects after the relay drops the socket and re-issues subscriptions" do
    relay = FakeRelay.start()
    conn = start_connection(relay, backoff_ms: 50)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    :ok = Connection.subscribe(conn, "s", [Filter.new(kinds: [1])])
    assert_receive {:relay_in, ["REQ", "s", _filter]}, 2_000

    FakeRelay.drop(relay)
    assert_receive {:nostr, ^url, {:disconnected, _reason}}, 2_000
    assert_receive {:nostr, ^url, :connected}, 5_000
    assert_receive {:relay_in, ["REQ", "s", _filter]}, 2_000
    assert Connection.status(conn) == :connected
  end

  test "a relay that is not listening stays disconnected and keeps retrying" do
    url = "ws://127.0.0.1:1/"
    conn = start_connection(%{url: url}, backoff_ms: 50)

    assert_receive {:nostr, ^url, {:disconnected, _reason}}, 2_000
    assert Connection.status(conn) in [:connecting, :disconnected]
    assert_receive {:nostr, ^url, {:disconnected, _reason}}, 2_000
  end

  test "a malformed inbound EVENT is dropped, not crashed on" do
    relay = FakeRelay.start()
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000
    :ok = Connection.subscribe(conn, "s", [Filter.new(kinds: [1])])
    assert_receive {:nostr, ^url, {:eose, "s"}}, 2_000

    FakeRelay.push(relay, ["EVENT", "s", %{"id" => 1}])

    FakeRelay.push(relay, [
      "EVENT",
      "s",
      Event.to_map(%{signed("bad") | sig: String.duplicate("0", 128)})
    ])

    refute_receive {:nostr, ^url, {:event, "s", _event}}, 300
    assert Process.alive?(conn)
    assert Connection.status(conn) == :connected
  end
end
