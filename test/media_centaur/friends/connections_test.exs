defmodule MediaCentaur.Friends.ConnectionsTest do
  use MediaCentaur.DataCase, async: false

  import ExUnit.CaptureLog

  @moduletag :capture_log

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Connections
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.FakeRelay
  alias MediaCentaur.Nostr.Filter
  alias MediaCentaur.Nostr.Keys

  setup do
    Identity.ensure()
    owner = start_supervised!({Connections.Owner, backoff_ms: 50})
    Connections.Owner.__sync_for_test__(owner)
    Friends.subscribe_connections()
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
    {:ok, _row} = Friends.add_relay(relay.url)
    Connections.Owner.__sync_for_test__()

    url = relay.url
    assert_receive {:relay_connection, ^url, :connected}, 3_000
    assert %{^url => %{state: :connected}} = Connections.status()
  end

  test "removing a relay stops its connection" do
    relay = FakeRelay.start()
    {:ok, _row} = Friends.add_relay(relay.url)
    assert_receive {:relay_connection, _url, :connected}, 3_000

    :ok = Friends.remove_relay(relay.url)
    Connections.Owner.__sync_for_test__()
    refute Map.has_key?(Connections.status(), relay.url)
  end

  test "an auth-required relay is authenticated with the identity" do
    relay = FakeRelay.start(auth: true)
    {:ok, _row} = Friends.add_relay(relay.url)

    assert_receive {:relay_connection, _url, {:auth, :ok}}, 3_000
    assert_receive {:relay_in, ["AUTH", %{"pubkey" => pubkey}]}, 3_000
    assert pubkey == Identity.pubkey()
  end

  test "identity replacement restarts the connections" do
    relay = FakeRelay.start()
    {:ok, _row} = Friends.add_relay(relay.url)
    assert_receive {:relay_connection, _url, :connected}, 3_000

    :ok = Identity.import_nsec(Keys.to_nsec(Keys.generate()))
    Connections.Owner.__sync_for_test__()
    assert_receive {:relay_connection, _url, :connected}, 3_000
  end

  test "status/0 is empty when no owner runs" do
    stop_supervised!(Connections.Owner)
    assert Connections.status() == %{}
  end

  test "a relay that rejects publishes surfaces the reason as last_error and logs it" do
    relay = FakeRelay.start(accept: false, reason: "blocked: not on the allowlist")

    log =
      capture_log(fn ->
        {:ok, _row} = Friends.add_relay(relay.url)
        assert_receive {:relay_connection, url, :connected}, 3_000

        Connections.publish(signed("x"))

        assert_receive {:relay_connection, ^url, {:ok, _id, false, "blocked: not on the allowlist"}},
                       3_000

        assert %{^url => %{last_error: "blocked: not on the allowlist"}} = Connections.status()
      end)

    assert log =~ "rejected a recommendation"
    assert log =~ "blocked: not on the allowlist"
  end

  test "a successful auth leaves no error behind" do
    relay = FakeRelay.start(auth: true)
    {:ok, _row} = Friends.add_relay(relay.url)

    assert_receive {:relay_connection, url, {:auth, :ok}}, 3_000
    Connections.Owner.__sync_for_test__()
    assert %{^url => %{state: :connected, last_error: nil}} = Connections.status()
  end

  test "a NOTICE is not an error; a CLOSED is" do
    relay = FakeRelay.start()
    {:ok, _row} = Friends.add_relay(relay.url)
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

  test "publish/2 and subscribe/3 address one relay" do
    first = FakeRelay.start()
    second = FakeRelay.start()
    {:ok, _row} = Friends.add_relay(first.url)
    {:ok, _row} = Friends.add_relay(second.url)
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
