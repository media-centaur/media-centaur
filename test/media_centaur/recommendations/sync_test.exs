defmodule MediaCentaur.Recommendations.SyncTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.FakeRelay
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Recommendations
  alias MediaCentaur.Recommendations.Sync
  alias MediaCentaur.Recommendations.Translation
  alias MediaCentaur.Secret
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title

  @moduletag :capture_log

  @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  setup do
    TmdbStubs.setup_tmdb_client()
    Identity.ensure()
    {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
    start_supervised!({Connections.Owner, backoff_ms: 50})
    start_supervised!(Sync)
    Recommendations.subscribe()
    :ok
  end

  defp title(id), do: Title.new!(%{tmdb_id: id, media_type: :movie, name: "Sample Movie #{id}"})

  defp friend_event(id),
    do: Event.sign(Translation.to_event(title(id), "from a friend", @friend_pubkey), @friend_secret)

  test "on connect, a friend's stored recommendation lands in the feed" do
    relay = FakeRelay.start(events: [friend_event(1)])
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:recommendation_received, _event}, 5_000
    assert [%{recommendation: %{tmdb_id: 1}, nickname: "Sample Friend"}] = Recommendations.list_feed()
    await_supervised_tasks()
  end

  test "own recommendations the relay lacks are published after its EOSE" do
    {:ok, _rec} = Recommendations.recommend(title(7), "mine")
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in, ["EVENT", %{"kind" => 32_160, "tags" => [["d", "tmdb:movie:7"]]}]}, 5_000
    await_supervised_tasks()
  end

  test "own recommendations the relay already has are not republished" do
    {:ok, _rec} = Recommendations.recommend(title(7), "mine")
    [own] = Recommendations.own_events()
    relay = FakeRelay.start(events: [own])
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in, ["REQ", "own:" <> _url, _filter]}, 5_000
    refute_receive {:relay_in, ["EVENT", _event]}, 1_000
    await_supervised_tasks()
  end

  test "a live event from a friend arrives through the feed subscription" do
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in,
                    ["REQ", "feed", %{"authors" => authors, "kinds" => [32_160, 5], "limit" => 500}]},
                   5_000

    assert @friend_pubkey in authors
    assert Identity.pubkey() in authors

    FakeRelay.push(relay, ["EVENT", "feed", Event.to_map(friend_event(2))])
    assert_receive {:recommendation_received, _event}, 5_000
    await_supervised_tasks()
  end

  test "adding a friend resubscribes the feed with the new author" do
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)
    assert_receive {:relay_in, ["REQ", "feed", _filter]}, 5_000

    other = Keys.generate()
    {:ok, _friend} = Social.add_friend(Keys.pubkey(other), "Another")

    assert_receive {:relay_in, ["REQ", "feed", %{"authors" => authors}]}, 5_000
    assert Keys.pubkey(other) in authors
  end

  test "events from strangers on the relay are ignored" do
    stranger = Keys.generate()
    event = Event.sign(Translation.to_event(title(3), nil, Keys.pubkey(stranger)), stranger)
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)
    assert_receive {:relay_in, ["REQ", "feed", _filter]}, 5_000

    FakeRelay.push(relay, ["EVENT", "feed", Event.to_map(event)])
    refute_receive {:recommendation_received, _event}, 500
    assert Recommendations.list_feed() == []
  end

  defp friend_event_at(id, created_at),
    do:
      Event.sign(
        %{Translation.to_event(title(id), "old", @friend_pubkey) | created_at: created_at},
        @friend_secret
      )

  test "the first connect has no cursor; a reconnect asks only for what is newer" do
    now = System.os_time(:second)
    relay = FakeRelay.start(events: [friend_event_at(1, now - 100)])
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in, ["REQ", "feed", first]}, 5_000
    refute Map.has_key?(first, "since")
    assert_receive {:recommendation_received, _event}, 5_000
    assert Social.synced_until(relay.url) == now - 100

    FakeRelay.drop(relay)
    assert_receive {:relay_in, ["REQ", "feed", %{"since" => since}]}, 5_000
    assert since == now - 100
    await_supervised_tasks()
  end

  test "a full page is followed by the next one, then the feed goes live again" do
    stop_supervised!(Sync)
    start_supervised!({Sync, page_limit: 2})
    now = System.os_time(:second)

    relay =
      FakeRelay.start(
        events: [
          friend_event_at(1, now - 30),
          friend_event_at(2, now - 20),
          friend_event_at(3, now - 10)
        ]
      )

    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in, ["REQ", "feed", %{"limit" => 2} = first]}, 5_000
    refute Map.has_key?(first, "until")
    assert_receive {:relay_in, ["REQ", "feed", %{"until" => until}]}, 5_000
    assert until == now - 20 - 1
    assert_receive {:relay_in, ["REQ", "feed", %{"since" => since} = live]}, 5_000
    refute Map.has_key?(live, "until")
    assert since == now - 10

    render_all = fn ->
      Recommendations.list_feed() |> Enum.map(& &1.recommendation.tmdb_id) |> Enum.sort()
    end

    assert_receive {:recommendation_received, _event}, 5_000
    Process.sleep(100)
    assert render_all.() == [1, 2, 3]
    await_supervised_tasks()
  end

  test "own deletions the relay lacks are published after its EOSE" do
    {:ok, rec} = Recommendations.recommend(title(7), "mine")
    {:ok, _gone} = Recommendations.delete(rec.id)
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in, ["EVENT", %{"kind" => 5, "tags" => [["a", coordinate] | _rest]}]}, 5_000
    assert coordinate == "32160:#{Identity.pubkey()}:tmdb:movie:7"
    refute_receive {:relay_in, ["EVENT", %{"kind" => 32_160}]}, 300
    await_supervised_tasks()
  end

  test "a friend's deletion arriving on the feed hides their recommendation" do
    now = System.os_time(:second)
    {:ok, _rec} = Recommendations.ingest(friend_event_at(4, now - 10))
    deletion = Event.sign(Translation.to_deletion(@friend_pubkey, :movie, 4, "x"), @friend_secret)
    relay = FakeRelay.start(events: [deletion])
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:recommendation_deleted, _event}, 5_000
    assert Recommendations.list_feed() == []
    await_supervised_tasks()
  end
end
