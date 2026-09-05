defmodule MediaCentaur.Nostr.ConnectionTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias MediaCentaur.Nostr.Connection
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.FakeRelay
  alias MediaCentaur.Nostr.Filter
  alias MediaCentaur.Nostr.SilentRelay

  @secret_hex String.duplicate("0", 63) <> "3"

  # Forwards every log event's message and metadata to the test process, so a
  # test can assert on the metadata a line carries (CaptureLog only sees text).
  defmodule LogEventProbe do
    def log(%{msg: {:string, message}, meta: meta}, %{config: %{pid: pid}}),
      do: send(pid, {:log_event, IO.chardata_to_string(message), meta})

    def log(_event, _config), do: :ok
  end

  defp probe_log_events do
    id = :"log_probe_#{System.unique_integer([:positive])}"
    :ok = :logger.add_handler(id, LogEventProbe, %{config: %{pid: self()}})
    ExUnit.Callbacks.on_exit(fn -> :logger.remove_handler(id) end)
  end

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

  test "a frame sharing the packet with the 101 upgrade is decoded, not dropped" do
    # Mint hands bytes that follow the 101 in the same packet to the
    # client as a `:data` response ahead of `:done`, before the socket is
    # upgraded. A relay that speaks first (an AUTH challenge on connect)
    # lands its frame there whenever the writes coalesce.
    relay = SilentRelay.start(greeting: ["EOSE", "s"])
    start_connection(relay)
    url = relay.url

    assert_receive {:nostr, ^url, :connected}, 2_000
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
    assert_receive {:nostr, ^url, {:disconnected, _reason, _retry}}, 2_000
    assert_receive {:nostr, ^url, :connected}, 5_000
    assert_receive {:relay_in, ["REQ", "s", _filter]}, 2_000
    assert Connection.status(conn) == :connected
  end

  test "a relay that is not listening stays disconnected and keeps retrying" do
    url = "ws://127.0.0.1:1/"
    conn = start_connection(%{url: url}, backoff_ms: 50)

    assert_receive {:nostr, ^url, {:disconnected, _reason, 50}}, 2_000
    assert Connection.status(conn) in [:connecting, :disconnected]
    assert_receive {:nostr, ^url, {:disconnected, _reason, 100}}, 2_000
  end

  test "a disconnect carries the wait before the next attempt, and it resets on connect" do
    relay = FakeRelay.start()
    _conn = start_connection(relay, backoff_ms: 50)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    FakeRelay.drop(relay)
    assert_receive {:nostr, ^url, {:disconnected, _reason, 50}}, 2_000
    assert_receive {:nostr, ^url, :connected}, 2_000

    FakeRelay.drop(relay)
    assert_receive {:nostr, ^url, {:disconnected, _reason, 50}}, 2_000
  end

  test "a relay that answers pings is heard from between events" do
    relay = FakeRelay.start()
    _conn = start_connection(relay, ping_interval_ms: 50)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    assert_receive {:nostr, ^url, :pong}, 2_000
    assert_receive {:nostr, ^url, :pong}, 2_000
  end

  test "a relay that stops answering pings is dropped as unresponsive and retried" do
    relay = SilentRelay.start()
    _conn = start_connection(relay, ping_interval_ms: 50, pong_timeout_ms: 100, backoff_ms: 50)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    assert_receive {:nostr, ^url, {:disconnected, :unresponsive, 50}}, 2_000
    assert_receive {:nostr, ^url, :connected}, 2_000
  end

  test "the first failed attempt logs once; the retries that follow do not" do
    # `capture_log` is global: a concurrent test dialling the same
    # unreachable relay lands in this capture too. The path makes the
    # URL, and so the logged line, this test's own.
    url = "ws://127.0.0.1:1/#{System.unique_integer([:positive])}"
    line = "could not connect to #{url}: connection refused"

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        start_connection(%{url: url}, backoff_ms: 20)
        assert_receive {:nostr, ^url, {:disconnected, _reason, 20}}, 2_000
        assert_receive {:nostr, ^url, {:disconnected, _reason, 40}}, 2_000
        assert_receive {:nostr, ^url, {:disconnected, _reason, 80}}, 2_000
      end)

    assert length(String.split(log, line)) == 2
  end

  test "a failed connect is logged for the console only — the Social probe owns the fault" do
    probe_log_events()
    url = "ws://127.0.0.1:1/"

    start_connection(%{url: url}, backoff_ms: 20)
    assert_receive {:nostr, ^url, {:disconnected, _reason, 20}}, 2_000

    assert_receive {:log_event, "could not connect to " <> _rest, meta}, 2_000
    assert meta[:mc_incident] == :skip
  end

  test "a lost connection is logged for the console only — the Social probe owns the fault" do
    probe_log_events()
    relay = FakeRelay.start()
    start_connection(relay, backoff_ms: 20)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    FakeRelay.drop(relay)
    assert_receive {:nostr, ^url, {:disconnected, _reason, _backoff}}, 2_000

    assert_receive {:log_event, "lost " <> _rest, meta}, 2_000
    assert meta[:mc_incident] == :skip
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

  test "hostile frames with the wrong types are ignored, not crashed on" do
    relay = FakeRelay.start()
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    for frame <- [
          ["EVENT", %{}, %{}],
          ["EOSE", 7],
          ["CLOSED", 1, 2],
          ["OK", 1, "yes", 3],
          ["NOTICE", %{}],
          ["AUTH", 5]
        ] do
      FakeRelay.push(relay, frame)
    end

    # A well-formed exchange after them proves the process kept serving.
    :ok = Connection.subscribe(conn, "s", [Filter.new(kinds: [1])])
    assert_receive {:nostr, ^url, {:eose, "s"}}, 2_000
    assert Process.alive?(conn)
    assert Connection.status(conn) == :connected
  end

  test "a CLOSED frame is reported as {:closed, sub_id, reason}" do
    relay = FakeRelay.start()
    conn = start_connection(relay)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    FakeRelay.push(relay, ["CLOSED", "s", "auth-required: not authenticated"])
    assert_receive {:nostr, ^url, {:closed, "s", "auth-required: not authenticated"}}, 2_000
    assert Connection.status(conn) == :connected
  end

  test "a publish while disconnected is dropped, not queued" do
    relay = FakeRelay.start()
    conn = start_connection(relay, backoff_ms: 5_000)
    url = relay.url
    assert_receive {:nostr, ^url, :connected}, 2_000

    FakeRelay.drop(relay)
    assert_receive {:nostr, ^url, {:disconnected, _reason, _retry}}, 2_000

    assert :ok = Connection.publish(conn, signed("dropped"))
    refute_receive {:relay_in, ["EVENT", _map]}, 300
    assert Process.alive?(conn)
  end
end
