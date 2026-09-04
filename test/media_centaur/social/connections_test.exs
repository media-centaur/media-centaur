defmodule MediaCentaur.Social.ConnectionsTest do
  use MediaCentaur.DataCase, async: false

  @moduletag :capture_log

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.FakeRelay
  alias MediaCentaur.Nostr.Filter
  alias MediaCentaur.Nostr.Keys

  setup do
    Identity.ensure()
    owner = start_supervised!({Connections.Owner, backoff_ms: 50})
    Connections.Owner.__sync_for_test__(owner)
    Social.subscribe_connections()
    %{owner: owner}
  end

  defp signed(content) do
    Event.sign(
      Event.new(%{created_at: System.os_time(:second), kind: 1, tags: [], content: content}),
      Identity.secret()
    )
  end

  test "connects to every relay row at boot and reports status" do
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)
    Connections.Owner.__sync_for_test__()

    url = relay.url
    assert_receive {:relay_connection, ^url, :connected}, 3_000
    assert %{^url => %{state: :connected}} = Connections.status()
  end

  test "removing a relay stops its connection" do
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)
    assert_receive {:relay_connection, _url, :connected}, 3_000

    :ok = Social.remove_relay(relay.url)
    Connections.Owner.__sync_for_test__()
    refute Map.has_key?(Connections.status(), relay.url)
  end

  test "an auth-required relay is authenticated with the identity" do
    relay = FakeRelay.start(auth: true)
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_connection, _url, {:auth, :ok}}, 3_000
    assert_receive {:relay_in, ["AUTH", %{"pubkey" => pubkey}]}, 3_000
    assert pubkey == Identity.pubkey()
  end

  test "identity replacement restarts the connections" do
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)
    assert_receive {:relay_connection, _url, :connected}, 3_000

    :ok = Identity.import_nsec(Keys.to_nsec(Keys.generate()))
    Connections.Owner.__sync_for_test__()
    assert_receive {:relay_connection, _url, :connected}, 3_000
  end

  test "status/0 is empty when no owner runs" do
    stop_supervised!(Connections.Owner)
    assert Connections.status() == %{}
  end

  test "a relay that rejects publishes surfaces the reason as last_error" do
    relay = FakeRelay.start(accept: false, reason: "blocked: not on the allowlist")
    {:ok, _row} = Social.add_relay(relay.url)
    assert_receive {:relay_connection, url, :connected}, 3_000

    Connections.publish(signed("x"))

    assert_receive {:relay_connection, ^url, {:ok, _id, false, "blocked: not on the allowlist"}}, 3_000
    assert %{^url => %{last_error: "blocked: not on the allowlist"}} = Connections.status()
  end

  test "a successful auth leaves no error behind" do
    relay = FakeRelay.start(auth: true)
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_connection, url, {:auth, :ok}}, 3_000
    Connections.Owner.__sync_for_test__()
    assert %{^url => %{state: :connected, last_error: nil}} = Connections.status()
  end

  test "a NOTICE is not an error; a CLOSED is" do
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)
    assert_receive {:relay_connection, url, :connected}, 3_000

    FakeRelay.push(relay, ["NOTICE", "restarting for maintenance"])
    assert_receive {:relay_connection, ^url, {:notice, "restarting for maintenance"}}, 3_000
    Connections.Owner.__sync_for_test__()
    assert %{^url => %{state: :connected, last_error: nil}} = Connections.status()

    FakeRelay.push(relay, ["CLOSED", "feed", "auth-required: not authenticated"])
    assert_receive {:relay_connection, ^url, {:closed, "feed", _reason}}, 3_000
    Connections.Owner.__sync_for_test__()
    assert %{^url => %{last_error: "auth-required: not authenticated"}} = Connections.status()
  end

  describe "apply_message/2 — an entry records when its state began" do
    test "a state change stamps `since`; a message that only records an error keeps it" do
      blank = Connections.blank_entry()
      assert %{state: :connecting, since: %DateTime{}} = blank

      connected = Connections.apply_message(blank, :connected)
      assert connected.state == :connected
      assert DateTime.compare(connected.since, blank.since) in [:gt, :eq]

      # Re-affirming the state the entry is already in keeps the onset.
      assert Connections.apply_message(connected, :connected).since == connected.since

      closed = Connections.apply_message(connected, {:closed, "feed", "nope"})
      assert closed.since == connected.since
      assert closed.last_error == "nope"

      dropped = Connections.apply_message(connected, {:disconnected, :closed_by_relay, 1_000})
      assert dropped.state == :disconnected
      assert DateTime.compare(dropped.since, connected.since) in [:gt, :eq]
    end
  end

  describe "apply_message/2 — the entry says why, when it retries, and when it was last heard" do
    test "a blank entry has heard nothing and has no retry" do
      assert %{last_heard_at: nil, retry_at: nil} = Connections.blank_entry()
    end

    test "a disconnect carries a plain reason and the next attempt" do
      before = DateTime.utc_now()

      entry =
        Connections.apply_message(
          Connections.blank_entry(),
          {:disconnected, %Mint.TransportError{reason: :econnrefused}, 30_000}
        )

      assert entry.state == :disconnected
      assert entry.last_error == "connection refused"
      assert DateTime.diff(entry.retry_at, before, :second) in 29..31
      assert entry.last_heard_at == nil
    end

    test "connecting clears the retry and counts as being heard from" do
      dropped =
        Connections.apply_message(Connections.blank_entry(), {:disconnected, :closed_by_relay, 1_000})

      connected = Connections.apply_message(dropped, :connected)

      assert connected.retry_at == nil
      assert %DateTime{} = connected.last_heard_at
    end

    test "a pong is heard without changing the state" do
      connected = Connections.apply_message(Connections.blank_entry(), :connected)
      heard = Connections.apply_message(connected, :pong)

      assert heard.state == :connected
      assert heard.since == connected.since
      assert DateTime.compare(heard.last_heard_at, connected.last_heard_at) in [:gt, :eq]
    end

    test "EOSE on the feed means synced; on any other subscription it does not" do
      connected = Connections.apply_message(Connections.blank_entry(), :connected)

      assert Connections.apply_message(connected, {:eose, "own:wss://a/"}).state == :connected
      synced = Connections.apply_message(connected, {:eose, Connections.feed_sub_id()})
      assert synced.state == :synced
      assert synced.last_error == nil
    end

    test "a reconnect after syncing starts over at connected" do
      synced =
        Connections.blank_entry()
        |> Connections.apply_message(:connected)
        |> Connections.apply_message({:eose, Connections.feed_sub_id()})

      assert Connections.apply_message(synced, :connected).state == :connected
    end

    test "the feed being closed drops synced back to connected with the reason" do
      synced =
        Connections.blank_entry()
        |> Connections.apply_message(:connected)
        |> Connections.apply_message({:eose, Connections.feed_sub_id()})

      closed =
        Connections.apply_message(synced, {:closed, Connections.feed_sub_id(), "error: overloaded"})

      assert closed.state == :connected
      assert closed.last_error == "error: overloaded"
    end

    test "the feed being closed as restricted is a rejected identity" do
      connected = Connections.apply_message(Connections.blank_entry(), :connected)

      rejected =
        Connections.apply_message(
          connected,
          {:closed, Connections.feed_sub_id(), "restricted: this key is not a member of this relay"}
        )

      assert rejected.state == :auth_failed
      assert rejected.last_error == "restricted: this key is not a member of this relay"

      other_sub =
        Connections.apply_message(connected, {:closed, "own:wss://a/", "restricted: not a member"})

      assert other_sub.state == :connected
    end
  end

  test "publish/2 and subscribe/3 address one relay" do
    first = FakeRelay.start()
    second = FakeRelay.start()
    {:ok, _row} = Social.add_relay(first.url)
    {:ok, _row} = Social.add_relay(second.url)
    assert_receive {:relay_connection, _url, :connected}, 3_000
    assert_receive {:relay_connection, _url, :connected}, 3_000

    Connections.subscribe(first.url, "only-a", [Filter.new(kinds: [1])])
    assert_receive {:relay_in, ["REQ", "only-a", _filter]}, 2_000
    refute_receive {:relay_in, ["REQ", "only-a", _filter]}, 300

    Connections.publish(second.url, signed("x"))
    assert_receive {:relay_in, ["EVENT", %{"content" => "x"}]}, 2_000
    refute_receive {:relay_in, ["EVENT", _event]}, 300
  end
end
