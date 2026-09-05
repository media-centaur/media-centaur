defmodule MediaCentaur.ActivitiesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory, only: [force_attrs: 2]

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Activities
  alias MediaCentaur.Activities.Events.Deleted
  alias MediaCentaur.Activities.Events.Received
  alias MediaCentaur.Activities.Events.Sent
  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Activities.Translation
  alias MediaCentaur.Secret
  alias MediaCentaur.TmdbStubs
  alias MediaCentaur.TMDB.Title

  @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  # No identity here on purpose: `recommend/2` creates one, and ingesting a
  # friend's event never needs one — so the tests that want an identity get
  # it from the code under test.
  setup do
    TmdbStubs.setup_tmdb_client()
    :ok
  end

  defp title(id \\ 603),
    do: Title.new!(%{tmdb_id: id, media_type: :movie, name: "Sample Movie #{id}", year: "1999"})

  defp friend_event(title, note, created_at, acted_at \\ nil, sentiment \\ :like) do
    opts = [created_at: created_at, acted_at: acted_at || created_at]

    Event.sign(
      Translation.to_event(
        :recommendation,
        title,
        [note: note, sentiment: sentiment],
        @friend_pubkey,
        opts
      ),
      @friend_secret
    )
  end

  defp wire_time(%DateTime{} = at), do: DateTime.to_unix(at)

  describe "recommend/3" do
    test "signs with the identity, stores it as a sent recommendation, and broadcasts" do
      Activities.subscribe()

      assert {:ok, %Activity{} = rec} = Activities.recommend(title(), :like, "Go.")
      assert rec.author_pubkey == Identity.pubkey()
      assert rec.note == "Go."
      assert {:ok, event} = Event.from_map(rec.raw_event)
      assert Event.verify(event) == :ok

      assert_receive {:activity_sent, %Sent{id: id}}, 500
      assert id == rec.id
      assert [%Activity{id: ^id}] = Activities.list_sent()

      assert [%{activity: %Activity{id: ^id}, nickname: nil, own?: true}] =
               Activities.list_feed()

      await_supervised_tasks()
    end

    test "re-recommending the same title replaces the record" do
      {:ok, first} = Activities.recommend(title(), :like, "first")
      {:ok, second} = Activities.recommend(title(), :like, "second")

      assert first.id == second.id
      assert Activities.list_sent() |> hd() |> Map.get(:note) == "second"
      assert length(Activities.own_events()) == 1

      await_supervised_tasks()
    end

    test "rejects a note over 500 characters and stores nothing" do
      long_note = String.duplicate("a", 501)

      assert {:error, :note_too_long} = Activities.recommend(title(), :like, long_note)
      assert Activities.list_sent() == []
    end

    test "a note at exactly 500 characters is accepted" do
      note = String.duplicate("a", 500)

      assert {:ok, rec} = Activities.recommend(title(), :like, note)
      assert rec.note == note

      await_supervised_tasks()
    end

    test "a note is trimmed before the length check and blank becomes nil" do
      assert {:ok, rec} = Activities.recommend(title(), :like, "  Go.  ")
      assert rec.note == "Go."

      assert {:ok, rec2} = Activities.recommend(title(2), :like, "   ")
      assert rec2.note == nil

      await_supervised_tasks()
    end
  end

  describe "recommend/3 sentiment" do
    test "stores the sentiment on the row and on the wire" do
      assert {:ok, %Activity{sentiment: :love} = rec} = Activities.recommend(title(), :love, nil)
      assert {:ok, event} = Event.from_map(rec.raw_event)
      assert %{"sentiment" => "love"} = Jason.decode!(event.content)
      assert {:ok, %Activity{sentiment: :like}} = Activities.recommend(title(2), :like, nil)
      await_supervised_tasks()
    end
  end

  describe "recommendations_for/1" do
    test "the live recommendations per title: friend rows named, own rows marked, newest first" do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, theirs} = Activities.ingest(friend_event(title(), "theirs", 1_700_000_000, nil, :love))
      {:ok, mine} = Activities.recommend(title(), :like, "mine")
      {:ok, other} = Activities.ingest(friend_event(title(604), "other", 1_700_000_000))
      {:ok, withdrawn} = Activities.recommend(title(605), :like, nil)
      {:ok, _tombstone} = Activities.delete(withdrawn.id)

      watched =
        Event.sign(
          Translation.to_event(:watched, title(), [episode: nil], @friend_pubkey,
            created_at: 1_700_000_000
          ),
          @friend_secret
        )

      {:ok, _watched} = Activities.ingest(watched)

      result =
        Activities.recommendations_for([{603, :movie}, {604, :movie}, {605, :movie}, {999, :movie}])

      theirs_id = theirs.id
      mine_id = mine.id
      other_id = other.id

      assert %{
               {603, :movie} => [
                 %{activity: %Activity{id: ^mine_id, sentiment: :like}, nickname: nil, own?: true},
                 %{
                   activity: %Activity{id: ^theirs_id, sentiment: :love},
                   nickname: "Sample Friend",
                   own?: false
                 }
               ],
               {604, :movie} => [
                 %{activity: %Activity{id: ^other_id}, nickname: "Sample Friend", own?: false}
               ]
             } = result

      assert map_size(result) == 2
      await_supervised_tasks()
    end

    test "nothing for no refs, and nothing from a former friend" do
      assert Activities.recommendations_for([]) == %{}

      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _rec} = Activities.ingest(friend_event(title(), "theirs", 1_700_000_000))
      assert %{{603, :movie} => [_row]} = Activities.recommendations_for([{603, :movie}])

      :ok = Social.remove_friend(@friend_pubkey)
      assert Activities.recommendations_for([{603, :movie}]) == %{}
      await_supervised_tasks()
    end
  end

  describe "ingest/1" do
    test "accepts a friend's verified event, decorates the feed with the nickname, broadcasts" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      Activities.subscribe()
      event = friend_event(title(), "Great.", 1_700_000_000)

      assert {:ok, %Activity{}} = Activities.ingest(event)
      assert_receive {:activity_received, %Received{author_pubkey: @friend_pubkey}}, 500

      assert [%{activity: %Activity{note: "Great."}, nickname: "Sample Friend"}] =
               Activities.list_feed()

      await_supervised_tasks()
    end

    test "a newer event replaces, an older one is ignored, the same one is a no-op" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, first} = Activities.ingest(friend_event(title(), "one", 1_700_000_000))

      assert {:ok, newer} = Activities.ingest(friend_event(title(), "two", 1_700_000_100))
      assert newer.id == first.id
      assert newer.note == "two"

      assert :ignored = Activities.ingest(friend_event(title(), "stale", 1_699_999_000))
      assert :ignored = Activities.ingest(friend_event(title(), "two", 1_700_000_100))
      assert [%{activity: %{note: "two"}}] = Activities.list_feed()

      await_supervised_tasks()
    end

    test "rejects a non-friend author and an invalid signature" do
      event = friend_event(title(), "x", 1_700_000_000)
      assert {:error, :unknown_author} = Activities.ingest(event)

      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      # A well-formed signature over a *different* event: the shape is
      # valid, the signature is not this event's.
      other = friend_event(title(604), "y", 1_700_000_000)
      assert {:error, :bad_signature} = Activities.ingest(%{event | sig: other.sig})
      assert Activities.list_feed() == []
    end

    test "own events arriving from a relay are stored once and shown as own" do
      {:ok, rec} = Activities.recommend(title(), :like, "mine")
      [event] = Activities.own_events()

      assert :ignored = Activities.ingest(event)

      assert [%{activity: %Activity{id: id}, nickname: nil, own?: true}] =
               Activities.list_feed()

      assert id == rec.id

      await_supervised_tasks()
    end
  end

  test "feed rows come newest first" do
    {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
    {:ok, _one} = Activities.ingest(friend_event(title(1), "a", 1_700_000_000))
    {:ok, _two} = Activities.ingest(friend_event(title(2), "b", 1_700_000_500))

    assert [%{activity: %{tmdb_id: 2}}, %{activity: %{tmdb_id: 1}}] =
             Activities.list_feed()

    await_supervised_tasks()
  end

  test "before an identity exists nothing is sent and a friend's recommendation still lands" do
    {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
    refute Identity.present?()

    {:ok, _rec} = Activities.ingest(friend_event(title(), "hi", 1_700_000_000))

    assert [%{activity: %{note: "hi"}}] = Activities.list_feed()
    assert Activities.list_sent() == []
    assert Activities.own_events() == []

    await_supervised_tasks()
  end

  test "artwork holds cover every stored title" do
    {:ok, _rec} = Activities.recommend(title(9), :like, nil)
    assert MapSet.member?(Activities.TmdbArtworkHolds.holds(), {:movie, 9})
    await_supervised_tasks()
  end

  describe "counts/0" do
    test "with no identity, everything counts as received" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _one} = Activities.ingest(friend_event(title(1), "a", 1_700_000_000))
      {:ok, _two} = Activities.ingest(friend_event(title(2), "b", 1_700_000_500))

      assert Activities.counts() == %{
               sent: 0,
               received: 2,
               last_received_at: DateTime.from_unix!(1_700_000_500)
             }

      await_supervised_tasks()
    end

    test "splits sent from received and finds the newest received acted_at" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _sent} = Activities.recommend(title(3), :like, "mine")
      {:ok, _one} = Activities.ingest(friend_event(title(1), "a", 1_700_000_000))
      {:ok, _two} = Activities.ingest(friend_event(title(2), "b", 1_700_000_500))

      assert Activities.counts() == %{
               sent: 1,
               received: 2,
               last_received_at: DateTime.from_unix!(1_700_000_500)
             }

      await_supervised_tasks()
    end

    test "with nothing stored, zero counts and no last_received_at" do
      assert Activities.counts() == %{sent: 0, received: 0, last_received_at: nil}
    end
  end

  defp friend_deletion(title, created_at) do
    Event.sign(
      %{
        Translation.to_deletion(:recommendation, @friend_pubkey, title.media_type, title.tmdb_id, "x")
        | created_at: created_at
      },
      @friend_secret
    )
  end

  describe "delete/1" do
    test "tombstones an own row, hides it everywhere, republishes the deletion, broadcasts" do
      Activities.subscribe()
      {:ok, rec} = Activities.recommend(title(), :like, "mine")

      assert {:ok, %Activity{deleted_at: %DateTime{}, deletion_event: %{"kind" => 5}} = gone} =
               Activities.delete(rec.id)

      assert Activity.deleted?(gone)
      assert Activities.list_feed() == []
      assert Activities.list_sent() == []
      assert %{sent: 0, received: 0} = Activities.counts()

      assert [%Event{kind: 5} = deletion] = Activities.own_events()
      assert Event.verify(deletion) == :ok
      assert Event.tag_value(deletion, "a") == "32160:#{Identity.pubkey()}:tmdb:movie:603"

      id = rec.id
      assert_receive {:activity_deleted, %Deleted{id: ^id}}, 500
      await_supervised_tasks()
    end

    test "refuses a friend's row and an unknown id; deleting twice is a no-op" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, theirs} = Activities.ingest(friend_event(title(), "theirs", System.os_time(:second)))
      assert {:error, :not_own} = Activities.delete(theirs.id)
      assert {:error, :not_found} = Activities.delete(Ecto.UUID.generate())

      {:ok, mine} = Activities.recommend(title(9), :like, nil)
      {:ok, gone} = Activities.delete(mine.id)
      assert {:ok, ^gone} = Activities.delete(mine.id)
      await_supervised_tasks()
    end

    test "a stale copy of the withdrawn recommendation is ignored; recommending again revives it" do
      {:ok, rec} = Activities.recommend(title(), :like, "mine")
      {:ok, stale} = Event.from_map(rec.raw_event)
      {:ok, _gone} = Activities.delete(rec.id)

      assert :ignored = Activities.ingest(stale)
      assert Activities.list_sent() == []

      {:ok, again} = Activities.recommend(title(), :like, "again")
      assert again.id == rec.id
      refute Activity.deleted?(again)
      assert [%{note: "again"}] = Activities.list_sent()
      assert [%Event{kind: 32_160}] = Activities.own_events()
      await_supervised_tasks()
    end
  end

  # The relay keeps one record per address and, on a `created_at` tie,
  # keeps what it holds (a deletion beating a recommendation). An own event
  # stamped no later than the row it supersedes would be discarded there
  # while replacing the row here, and republished on every connect.
  describe "own events are stamped after what the row holds" do
    test "a re-recommendation is stamped after the recommendation it replaces" do
      {:ok, rec} = Activities.recommend(title(), :like, "first")
      ahead = wire_time(ahead_of_now())
      force_attrs(rec, raw_event: Map.put(rec.raw_event, "created_at", ahead))

      {:ok, again} = Activities.recommend(title(), :like, "second")
      assert again.raw_event["created_at"] > ahead
      # The domain time is when the person acted, not the wire stamp.
      assert DateTime.before?(again.acted_at, DateTime.from_unix!(ahead))
      await_supervised_tasks()
    end

    test "a revival is stamped after the tombstone" do
      {:ok, rec} = Activities.recommend(title(), :like, "mine")
      {:ok, gone} = Activities.delete(rec.id)
      ahead = wire_time(ahead_of_now())
      force_attrs(gone, deletion_event: Map.put(gone.deletion_event, "created_at", ahead))

      {:ok, again} = Activities.recommend(title(), :like, "again")
      assert again.raw_event["created_at"] > ahead
      await_supervised_tasks()
    end

    test "a deletion is stamped no earlier than the recommendation it withdraws" do
      {:ok, rec} = Activities.recommend(title(), :like, "mine")
      ahead = wire_time(ahead_of_now())
      force_attrs(rec, raw_event: Map.put(rec.raw_event, "created_at", ahead))

      {:ok, gone} = Activities.delete(rec.id)
      assert gone.deletion_event["created_at"] >= ahead
      assert DateTime.before?(gone.deleted_at, DateTime.from_unix!(ahead))
      await_supervised_tasks()
    end

    defp ahead_of_now, do: DateTime.utc_now() |> DateTime.add(100, :second) |> DateTime.truncate(:second)
  end

  describe "wire time and domain time" do
    setup do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      :ok
    end

    test "the payload's time is the row's acted_at; created_at decides which copy wins" do
      now = System.os_time(:second)
      {:ok, rec} = Activities.ingest(friend_event(title(), "a", now, now - 1_000))
      assert rec.acted_at == DateTime.from_unix!(now - 1_000)

      # Newer on the wire replaces, whatever the payload says.
      {:ok, rec} = Activities.ingest(friend_event(title(), "b", now + 1, now - 2_000))
      assert rec.note == "b"
      assert rec.acted_at == DateTime.from_unix!(now - 2_000)

      # Older on the wire is the stale copy, whatever the payload says.
      assert :ignored = Activities.ingest(friend_event(title(), "c", now - 5, now + 5_000))
      assert [%{activity: %{note: "b"}}] = Activities.list_feed()
      await_supervised_tasks()
    end

    test "a deletion's tag is the row's deleted_at; created_at decides whether it applies" do
      now = System.os_time(:second)
      {:ok, _rec} = Activities.ingest(friend_event(title(), "a", now))

      early_act_late_wire =
        Event.sign(
          Translation.to_deletion(:recommendation, @friend_pubkey, :movie, 603, nil,
            created_at: now + 1,
            deleted_at: now - 50
          ),
          @friend_secret
        )

      assert {:ok, %Activity{deleted_at: deleted_at}} = Activities.ingest(early_act_late_wire)
      assert deleted_at == DateTime.from_unix!(now - 50)
      await_supervised_tasks()
    end
  end

  describe "ingest/1 of a deletion" do
    setup do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      :ok
    end

    test "a friend's deletion tombstones their row and broadcasts" do
      Activities.subscribe()
      now = System.os_time(:second)
      {:ok, rec} = Activities.ingest(friend_event(title(), "theirs", now - 10))

      assert {:ok, %Activity{deleted_at: %DateTime{}}} =
               Activities.ingest(friend_deletion(title(), now))

      id = rec.id
      assert_receive {:activity_deleted, %Deleted{id: ^id, author_pubkey: @friend_pubkey}}, 500
      assert Activities.list_feed() == []

      # The withdrawn recommendation coming back off another relay stays hidden.
      assert :ignored = Activities.ingest(friend_event(title(), "theirs", now - 10))
      assert Activities.list_feed() == []

      # A newer recommendation revives it.
      assert {:ok, _revived} = Activities.ingest(friend_event(title(), "again", now + 10))
      assert [%{activity: %{note: "again"}}] = Activities.list_feed()
      await_supervised_tasks()
    end

    test "a deletion older than the recommendation, or for nothing stored, is ignored" do
      now = System.os_time(:second)
      {:ok, _rec} = Activities.ingest(friend_event(title(), "theirs", now))

      assert :ignored = Activities.ingest(friend_deletion(title(), now - 10))
      assert [_row] = Activities.list_feed()

      assert :ignored = Activities.ingest(friend_deletion(title(99), now))
      await_supervised_tasks()
    end

    test "a stranger's deletion and a bad signature are rejected" do
      stranger = MediaCentaur.Nostr.Keys.generate()
      pubkey = MediaCentaur.Nostr.Keys.pubkey(stranger)
      event = Event.sign(Translation.to_deletion(:recommendation, pubkey, :movie, 603, "x"), stranger)
      assert {:error, :unknown_author} = Activities.ingest(event)

      forged = %{friend_deletion(title(), System.os_time(:second)) | sig: String.duplicate("0", 128)}
      assert {:error, _reason} = Activities.ingest(forged)
    end
  end

  describe "watched/2 and tracking/1" do
    defp show, do: Title.new!(%{tmdb_id: 1399, media_type: :tv_series, name: "Sample Show"})
    defp episode(number), do: %Episode{season_number: 1, episode_number: number, name: nil}

    test "watched stores the episode and a later episode replaces the row" do
      Activities.subscribe()

      assert {:ok, %Activity{kind: :watched} = first} = Activities.watched(show(), episode(1))
      assert %Episode{season_number: 1, episode_number: 1} = first.episode
      assert_receive {:activity_sent, %Sent{kind: :watched, id: first_id}}, 500
      assert first_id == first.id

      assert {:ok, %Activity{id: ^first_id} = second} = Activities.watched(show(), episode(2))
      assert second.episode.episode_number == 2
      assert Activity.event_created_at(second) > Activity.event_created_at(first)
      assert [%Activity{kind: :watched, id: ^first_id}] = Activities.list_sent()
    end

    test "a watched movie has no episode, and kinds are separate rows for one title" do
      assert {:ok, %Activity{kind: :watched, episode: nil}} = Activities.watched(title(), nil)
      assert {:ok, %Activity{kind: :tracking}} = Activities.tracking(title())
      assert {:ok, %Activity{kind: :recommendation}} = Activities.recommend(title(), :like, nil)

      kinds = Activities.list_sent() |> Enum.map(& &1.kind) |> Enum.sort()
      assert kinds == [:recommendation, :tracking, :watched]
    end

    test "delete withdraws a watched row under its own kind" do
      Activities.subscribe()
      {:ok, watched} = Activities.watched(show(), episode(3))

      assert {:ok, %Activity{deleted_at: %DateTime{}} = tombstone} = Activities.delete(watched.id)
      assert {:ok, deletion} = Event.from_map(tombstone.deletion_event)
      assert Event.tag_value(deletion, "a") == "32161:#{Identity.pubkey()}:tmdb:tv_series:1399"
      assert_receive {:activity_deleted, %Deleted{kind: :watched}}, 500
      assert Activities.list_sent() == []
    end

    test "a friend's watched event is ingested with its kind" do
      Activities.subscribe()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sam")

      event =
        Event.sign(
          Translation.to_event(:watched, show(), [episode: episode(4)], @friend_pubkey),
          @friend_secret
        )

      assert {:ok, %Activity{kind: :watched, episode: %Episode{episode_number: 4}}} =
               Activities.ingest(event)

      assert_receive {:activity_received, %Received{kind: :watched}}, 500

      assert [%{activity: %Activity{kind: :watched}, nickname: "Sam", own?: false}] =
               Activities.list_feed()

      await_supervised_tasks()
    end
  end
end
