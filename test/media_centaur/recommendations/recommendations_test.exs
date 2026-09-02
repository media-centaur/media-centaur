defmodule MediaCentaur.RecommendationsTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Recommendations
  alias MediaCentaur.Recommendations.Events.Received
  alias MediaCentaur.Recommendations.Events.Sent
  alias MediaCentaur.Recommendations.Recommendation
  alias MediaCentaur.Recommendations.Translation
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

  defp friend_event(title, note, created_at) do
    Event.sign(
      %{Translation.to_event(title, note, @friend_pubkey) | created_at: created_at},
      @friend_secret
    )
  end

  describe "recommend/2" do
    test "signs with the identity, stores it as a sent recommendation, and broadcasts" do
      Recommendations.subscribe()

      assert {:ok, %Recommendation{} = rec} = Recommendations.recommend(title(), "Go.")
      assert rec.author_pubkey == Identity.pubkey()
      assert rec.note == "Go."
      assert {:ok, event} = Event.from_map(rec.raw_event)
      assert Event.verify(event) == :ok

      assert_receive {:recommendation_sent, %Sent{id: id}}, 500
      assert id == rec.id
      assert [%Recommendation{id: ^id}] = Recommendations.list_sent()

      assert [%{recommendation: %Recommendation{id: ^id}, nickname: nil, own?: true}] =
               Recommendations.list_feed()

      await_supervised_tasks()
    end

    test "re-recommending the same title replaces the record" do
      {:ok, first} = Recommendations.recommend(title(), "first")
      {:ok, second} = Recommendations.recommend(title(), "second")

      assert first.id == second.id
      assert Recommendations.list_sent() |> hd() |> Map.get(:note) == "second"
      assert length(Recommendations.own_events()) == 1

      await_supervised_tasks()
    end

    test "rejects a note over 500 characters and stores nothing" do
      long_note = String.duplicate("a", 501)

      assert {:error, :note_too_long} = Recommendations.recommend(title(), long_note)
      assert Recommendations.list_sent() == []
    end

    test "a note at exactly 500 characters is accepted" do
      note = String.duplicate("a", 500)

      assert {:ok, rec} = Recommendations.recommend(title(), note)
      assert rec.note == note

      await_supervised_tasks()
    end

    test "a note is trimmed before the length check and blank becomes nil" do
      assert {:ok, rec} = Recommendations.recommend(title(), "  Go.  ")
      assert rec.note == "Go."

      assert {:ok, rec2} = Recommendations.recommend(title(2), "   ")
      assert rec2.note == nil

      await_supervised_tasks()
    end
  end

  describe "ingest/1" do
    test "accepts a friend's verified event, decorates the feed with the nickname, broadcasts" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      Recommendations.subscribe()
      event = friend_event(title(), "Great.", 1_700_000_000)

      assert {:ok, %Recommendation{}} = Recommendations.ingest(event)
      assert_receive {:recommendation_received, %Received{author_pubkey: @friend_pubkey}}, 500

      assert [%{recommendation: %Recommendation{note: "Great."}, nickname: "Sample Friend"}] =
               Recommendations.list_feed()

      await_supervised_tasks()
    end

    test "a newer event replaces, an older one is ignored, the same one is a no-op" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, first} = Recommendations.ingest(friend_event(title(), "one", 1_700_000_000))

      assert {:ok, newer} = Recommendations.ingest(friend_event(title(), "two", 1_700_000_100))
      assert newer.id == first.id
      assert newer.note == "two"

      assert :ignored = Recommendations.ingest(friend_event(title(), "stale", 1_699_999_000))
      assert :ignored = Recommendations.ingest(friend_event(title(), "two", 1_700_000_100))
      assert [%{recommendation: %{note: "two"}}] = Recommendations.list_feed()

      await_supervised_tasks()
    end

    test "rejects a non-friend author and an invalid signature" do
      event = friend_event(title(), "x", 1_700_000_000)
      assert {:error, :unknown_author} = Recommendations.ingest(event)

      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      # A well-formed signature over a *different* event: the shape is
      # valid, the signature is not this event's.
      other = friend_event(title(604), "y", 1_700_000_000)
      assert {:error, :bad_signature} = Recommendations.ingest(%{event | sig: other.sig})
      assert Recommendations.list_feed() == []
    end

    test "own events arriving from a relay are stored once and shown as own" do
      {:ok, rec} = Recommendations.recommend(title(), "mine")
      [event] = Recommendations.own_events()

      assert :ignored = Recommendations.ingest(event)

      assert [%{recommendation: %Recommendation{id: id}, nickname: nil, own?: true}] =
               Recommendations.list_feed()

      assert id == rec.id

      await_supervised_tasks()
    end
  end

  test "feed rows come newest first" do
    {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
    {:ok, _one} = Recommendations.ingest(friend_event(title(1), "a", 1_700_000_000))
    {:ok, _two} = Recommendations.ingest(friend_event(title(2), "b", 1_700_000_500))

    assert [%{recommendation: %{tmdb_id: 2}}, %{recommendation: %{tmdb_id: 1}}] =
             Recommendations.list_feed()

    await_supervised_tasks()
  end

  test "before an identity exists nothing is sent and a friend's recommendation still lands" do
    {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
    refute Identity.present?()

    {:ok, _rec} = Recommendations.ingest(friend_event(title(), "hi", 1_700_000_000))

    assert [%{recommendation: %{note: "hi"}}] = Recommendations.list_feed()
    assert Recommendations.list_sent() == []
    assert Recommendations.own_events() == []

    await_supervised_tasks()
  end

  test "artwork holds cover every stored title" do
    {:ok, _rec} = Recommendations.recommend(title(9), nil)
    assert MapSet.member?(Recommendations.TmdbArtworkHolds.holds(), {:movie, 9})
    await_supervised_tasks()
  end

  describe "counts/0" do
    test "with no identity, everything counts as received" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _one} = Recommendations.ingest(friend_event(title(1), "a", 1_700_000_000))
      {:ok, _two} = Recommendations.ingest(friend_event(title(2), "b", 1_700_000_500))

      assert Recommendations.counts() == %{
               sent: 0,
               received: 2,
               last_received_at: DateTime.from_unix!(1_700_000_500)
             }

      await_supervised_tasks()
    end

    test "splits sent from received and finds the newest received recommended_at" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _sent} = Recommendations.recommend(title(3), "mine")
      {:ok, _one} = Recommendations.ingest(friend_event(title(1), "a", 1_700_000_000))
      {:ok, _two} = Recommendations.ingest(friend_event(title(2), "b", 1_700_000_500))

      assert Recommendations.counts() == %{
               sent: 1,
               received: 2,
               last_received_at: DateTime.from_unix!(1_700_000_500)
             }

      await_supervised_tasks()
    end

    test "with nothing stored, zero counts and no last_received_at" do
      assert Recommendations.counts() == %{sent: 0, received: 0, last_received_at: nil}
    end
  end
end
