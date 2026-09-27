defmodule MediaCentaur.Social.ProfileTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Events.ProfileUpdated
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Profile
  alias MediaCentaur.Social.Profile.Translation

  @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @friend_pubkey Keys.pubkey(@friend_secret)

  defp friend_profile(name, created_at),
    do: Event.sign(Translation.to_event(name, @friend_pubkey, created_at), @friend_secret)

  describe "save_profile/1" do
    test "mints the identity, stores the row, publishes, broadcasts; a blank name is refused" do
      refute Identity.present?()
      Social.subscribe()

      assert {:error, :name_required} = Social.save_profile("   ")
      refute Identity.present?()

      assert {:ok, %Profile{name: "Sample Name", created_at: first}} =
               Social.save_profile("  Sample Name ")

      assert Identity.present?()
      me = Identity.pubkey()
      assert_receive {:profile_updated, %ProfileUpdated{pubkey: ^me}}, 500
      assert %Profile{name: "Sample Name"} = Social.own_profile()

      # A second save within the same second is stamped strictly after the first.
      assert {:ok, %Profile{name: "Renamed", created_at: second}} = Social.save_profile("Renamed")
      assert second > first
      assert [%Event{kind: 12_160}] = Social.own_events()
    end
  end

  describe "ingest_profile/1" do
    test "a friend's verified profile is stored under their key; newer wins, a tie keeps the stored one" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")
      Social.subscribe()

      assert {:ok, %Profile{name: "One"}} = Social.ingest_profile(friend_profile("One", 1_700_000_000))
      assert_receive {:profile_updated, %ProfileUpdated{pubkey: @friend_pubkey}}, 500

      assert :ignored = Social.ingest_profile(friend_profile("Older", 1_699_999_999))
      assert :ignored = Social.ingest_profile(friend_profile("Tie", 1_700_000_000))
      assert {:ok, %Profile{name: "Two"}} = Social.ingest_profile(friend_profile("Two", 1_700_000_001))
      assert Social.people()[@friend_pubkey].published_name == "Two"
    end

    test "an unknown key and a malformed event are refused" do
      assert {:error, :unknown_author} = Social.ingest_profile(friend_profile("Nobody", 1))

      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")

      bad =
        Event.sign(
          Event.new(%{pubkey: @friend_pubkey, created_at: 1, kind: 12_160, tags: [], content: "x"}),
          @friend_secret
        )

      assert {:error, :bad_content} = Social.ingest_profile(bad)
    end
  end

  describe "pruning" do
    test "removing a friend removes their profile; replacing the identity removes the old own row" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")
      {:ok, _profile} = Social.ingest_profile(friend_profile("One", 1_700_000_000))
      :ok = Social.remove_friend(@friend_pubkey)
      assert Social.people() == %{}
      assert Repo.all(Profile) == []

      {:ok, _profile} = Social.save_profile("Me")
      old = Identity.pubkey()
      :ok = Social.import_identity(Keys.to_nsec(Secret.wrap(String.duplicate("0", 63) <> "5")))
      refute Identity.pubkey() == old
      assert Repo.all(Profile) == []
      assert Social.own_profile() == nil
    end
  end

  test "own_event_kind/1 names the own profile and nothing else" do
    {:ok, _profile} = Social.save_profile("Me")
    [event] = Social.own_events()
    assert Social.own_event_kind(event.id) == :profile
    assert Social.own_event_kind("nope") == nil
  end
end
