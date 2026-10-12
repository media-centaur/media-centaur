defmodule MediaCentaur.Social.MembersTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Events.MembersChanged
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Person
  alias MediaCentaur.Social.Profile
  alias MediaCentaur.Social.Profile.Translation, as: ProfileTranslation
  alias MediaCentaur.Social.RelayMember

  @group "wss://group.example"
  @secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @pubkey Keys.pubkey(@secret)

  defp profile_event(name),
    do:
      Event.sign(
        ProfileTranslation.to_event(%{name: name, avatar: nil, hue: nil}, @pubkey, 1_700_000_000),
        @secret
      )

  describe "note_member/2" do
    test "on a members-rule relay a key becomes a followed person; the first sighting broadcasts, later ones are silent" do
      {:ok, _relay} = Social.add_relay(@group, :members)
      Social.subscribe()

      assert :ok = Social.note_member(@group, String.upcase(@pubkey))
      assert_receive {:members_changed, %MembersChanged{url: "wss://group.example/"}}, 500
      assert Social.followed_key?(@pubkey)
      assert Social.list_friends() == []

      assert %{@pubkey => %Person{friend?: false, hidden: false, member_of: ["wss://group.example/"]}} =
               Social.people()

      assert :ok = Social.note_member(@group, @pubkey)
      refute_receive {:members_changed, _event}, 100
    end

    test "an added-rule relay, an unknown relay and the reader's own key are ignored" do
      {:ok, _relay} = Social.add_relay("wss://relay.example")
      assert :ignored = Social.note_member("wss://relay.example", @pubkey)
      assert :ignored = Social.note_member("wss://nowhere.example", @pubkey)
      refute Social.followed_key?(@pubkey)

      Identity.ensure()
      {:ok, _relay} = Social.add_relay(@group, :members)
      assert :ignored = Social.note_member(@group, Identity.pubkey())
      assert Social.people() |> Map.fetch!(Identity.pubkey()) |> Map.fetch!(:own?)
    end
  end

  describe "sweep_members/2" do
    test "forgets the members not seen since the connect, with their profiles, and broadcasts once" do
      {:ok, _relay} = Social.add_relay(@group, :members)
      :ok = Social.note_member(@group, @pubkey)
      {:ok, _profile} = Social.ingest_profile(profile_event("Sample Member"))
      connected_at = DateTime.utc_now()
      other = String.duplicate("b", 64)
      :ok = Social.note_member(@group, other)
      Social.subscribe()

      assert :ok = Social.sweep_members(@group, connected_at)
      assert_receive {:members_changed, %MembersChanged{url: "wss://group.example/"}}, 500
      refute Social.followed_key?(@pubkey)
      assert Social.followed_key?(other)
      refute Map.has_key?(Social.people(), @pubkey)
      assert Social.ingest_profile(profile_event("Back")) == {:error, :unknown_author}

      assert :ok = Social.sweep_members(@group, connected_at)
      refute_receive {:members_changed, _event}, 100
      assert :ignored = Social.sweep_members("wss://nowhere.example", connected_at)
    end

    test "a swept member who is also a friend stays a friend" do
      {:ok, _relay} = Social.add_relay(@group, :members)
      :ok = Social.note_member(@group, @pubkey)
      {:ok, _friend} = Social.add_friend(@pubkey, "Sample Friend")

      assert :ok = Social.sweep_members(@group, DateTime.utc_now())
      assert Social.followed_key?(@pubkey)
      assert %{@pubkey => %Person{friend?: true, member_of: []}} = Social.people()
    end
  end

  describe "a relay going" do
    test "removing a relay forgets its members; switching it to added does the same" do
      {:ok, _relay} = Social.add_relay(@group, :members)
      :ok = Social.note_member(@group, @pubkey)
      {:ok, _profile} = Social.ingest_profile(profile_event("Sample Member"))

      {:ok, _relay} = Social.set_follow(@group, :added)
      refute Social.followed_key?(@pubkey)
      assert Repo.aggregate(RelayMember, :count) == 0
      assert Repo.aggregate(Profile, :count) == 0

      {:ok, _relay} = Social.set_follow(@group, :members)
      :ok = Social.note_member(@group, @pubkey)
      :ok = Social.remove_relay(@group)
      refute Social.followed_key?(@pubkey)
      assert Repo.aggregate(RelayMember, :count) == 0
    end
  end
end
