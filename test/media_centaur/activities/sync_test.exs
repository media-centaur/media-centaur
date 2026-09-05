defmodule MediaCentaur.Activities.SyncTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.Console
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.FakeRelay
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Sync
  alias MediaCentaur.Activities.Translation
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
    Activities.subscribe()
    :ok
  end

  defp title(id), do: Title.new!(%{tmdb_id: id, media_type: :movie, name: "Sample Movie #{id}"})

  defp friend_event(id),
    do:
      Event.sign(
        Translation.to_event(:recommendation, title(id), [note: "from a friend"], @friend_pubkey),
        @friend_secret
      )

  test "on connect, a friend's stored recommendation lands in the feed" do
    relay = FakeRelay.start(events: [friend_event(1)])
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:activity_received, _event}, 5_000
    assert [%{activity: %{tmdb_id: 1}, nickname: "Sample Friend"}] = Activities.list_feed()
    await_supervised_tasks()
  end

  test "own recommendations the relay lacks are published after its EOSE" do
    {:ok, _rec} = Activities.recommend(title(7), "mine")
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in, ["EVENT", %{"kind" => 32_160, "tags" => [["d", "tmdb:movie:7"]]}]}, 5_000
    await_supervised_tasks()
  end

  test "own recommendations the relay already has are not republished" do
    {:ok, _rec} = Activities.recommend(title(7), "mine")
    [own] = Activities.own_events()
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
                    [
                      "REQ",
                      "feed",
                      %{"authors" => authors, "kinds" => [32_160, 32_161, 32_162, 5], "limit" => 500}
                    ]},
                   5_000

    assert @friend_pubkey in authors
    assert Identity.pubkey() in authors

    FakeRelay.push(relay, ["EVENT", "feed", Event.to_map(friend_event(2))])
    assert_receive {:activity_received, _event}, 5_000
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

    event =
      Event.sign(
        Translation.to_event(:recommendation, title(3), [note: nil], Keys.pubkey(stranger)),
        stranger
      )

    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)
    assert_receive {:relay_in, ["REQ", "feed", _filter]}, 5_000

    FakeRelay.push(relay, ["EVENT", "feed", Event.to_map(event)])
    refute_receive {:activity_received, _event}, 500
    assert Activities.list_feed() == []
  end

  defp friend_event_at(id, created_at),
    do:
      Event.sign(
        %{
          Translation.to_event(:recommendation, title(id), [note: "old"], @friend_pubkey)
          | created_at: created_at
        },
        @friend_secret
      )

  # No cursor: a relay holds one record per signer per title, so a friend
  # group's whole history is one page, and a `since` cursor would skip an
  # event published late with an older stamp (a withdrawal made offline).
  test "every connect reads the relay from the start; what is already stored is not news" do
    now = System.os_time(:second)
    relay = FakeRelay.start(events: [friend_event_at(1, now - 100)])
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in, ["REQ", "feed", first]}, 5_000
    refute Map.has_key?(first, "since")
    assert_receive {:activity_received, _event}, 5_000

    FakeRelay.drop(relay)
    # The reconnect sends "feed" twice (the owner replays its registered
    # subscription, then Sync re-issues it); neither carries a cursor.
    assert_receive {:relay_in, ["REQ", "feed", again]}, 5_000
    refute Map.has_key?(again, "since")
    refute_receive {:relay_in, ["REQ", "feed", %{"since" => _cursor}]}, 500
    refute_receive {:activity_received, _event}, 100
    assert [%{activity: %{tmdb_id: 1}}] = Activities.list_feed()
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
    assert_receive {:relay_in, ["REQ", "feed", %{"limit" => 2} = live]}, 5_000
    refute Map.has_key?(live, "until")
    refute Map.has_key?(live, "since")

    render_all = fn ->
      Activities.list_feed() |> Enum.map(& &1.activity.tmdb_id) |> Enum.sort()
    end

    assert_receive {:activity_received, _event}, 5_000
    # The feed row lands on another process after the event; poll it.
    eventually(fn -> render_all.() == [1, 2, 3] end)
    await_supervised_tasks()
  end

  test "own deletions the relay lacks are published after its EOSE" do
    {:ok, rec} = Activities.recommend(title(7), "mine")
    {:ok, _gone} = Activities.delete(rec.id)
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in, ["EVENT", %{"kind" => 5, "tags" => [["a", coordinate] | _rest]}]}, 5_000
    assert coordinate == "32160:#{Identity.pubkey()}:tmdb:movie:7"
    refute_receive {:relay_in, ["EVENT", %{"kind" => 32_160}]}, 300
    await_supervised_tasks()
  end

  test "a relay refusing an own event is logged by what was refused" do
    {:ok, rec} = Activities.recommend(title(7), "mine")
    {:ok, _gone} = Activities.delete(rec.id)
    relay = FakeRelay.start(accept: false, reason: "blocked: kind 5 is not stored by this relay")
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in, ["EVENT", %{"kind" => 5}]}, 5_000

    assert_logged(~r/rejected a deletion: blocked: kind 5 is not stored by this relay/)
    await_supervised_tasks()
  end

  test "a relay refusing an own recommendation is logged as such" do
    {:ok, _rec} = Activities.recommend(title(7), "mine")

    relay =
      FakeRelay.start(
        accept: false,
        reason: "restricted: the event author is not a member of this relay"
      )

    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:relay_in, ["EVENT", %{"kind" => 32_160}]}, 5_000

    assert_logged(~r/rejected a recommendation: restricted: the event author/)
    await_supervised_tasks()
  end

  # The verdict arrives after the EVENT frame the test saw, on another
  # process; the console buffer (batched, hence the flush) is the
  # observable, polled to a deadline.
  defp assert_logged(regex, timeout_ms \\ 2_000) do
    eventually(
      fn ->
        Console.Buffer.flush()
        Enum.any?(Console.Buffer.recent(), &Regex.match?(regex, &1.message))
      end,
      timeout: timeout_ms,
      message: fn ->
        "expected a console line matching #{inspect(regex)}, buffer holds: " <>
          inspect(Enum.map(Console.Buffer.recent(), & &1.message))
      end
    )
  end

  test "a friend's deletion arriving on the feed hides their recommendation" do
    now = System.os_time(:second)
    {:ok, _rec} = Activities.ingest(friend_event_at(4, now - 10))

    deletion =
      Event.sign(
        Translation.to_deletion(:recommendation, @friend_pubkey, :movie, 4, "x"),
        @friend_secret
      )

    relay = FakeRelay.start(events: [deletion])
    {:ok, _row} = Social.add_relay(relay.url)

    assert_receive {:activity_deleted, _event}, 5_000
    assert Activities.list_feed() == []
    await_supervised_tasks()
  end
end
