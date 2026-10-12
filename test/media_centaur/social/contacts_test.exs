defmodule MediaCentaur.Social.ContactsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Contact
  alias MediaCentaur.Social.Events.ContactChanged
  alias MediaCentaur.Social.Events.FriendAdded
  alias MediaCentaur.Social.Events.FriendRemoved
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Person
  alias MediaCentaur.Social.Profile.Translation, as: ProfileTranslation

  @secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @pubkey Keys.pubkey(@secret)

  defp profile_event(name),
    do:
      Event.sign(
        ProfileTranslation.to_event(%{name: name, avatar: nil, hue: nil}, @pubkey, 1_700_000_000),
        @secret
      )

  describe "add_friend/2" do
    test "accepts an npub, stores lowercase hex and the trimmed name, broadcasts" do
      Social.subscribe()
      npub = Keys.to_npub(@pubkey)

      assert {:ok,
              %Contact{pubkey: @pubkey, name_override: "Sample Friend", added_at: %DateTime{}} = contact} =
               Social.add_friend(npub, "  Sample Friend ")

      assert Contact.friend?(contact)
      assert_receive {:friend_added, %FriendAdded{pubkey: @pubkey}}, 500
      assert [%Contact{pubkey: @pubkey}] = Social.list_friends()
      assert Social.friend_pubkeys() == [@pubkey]
    end

    test "re-adding a key already on the roster changes nothing and broadcasts nothing" do
      Social.subscribe()

      {:ok, first} = Social.add_friend(String.upcase(@pubkey), "One")
      assert_receive {:friend_added, %FriendAdded{pubkey: @pubkey}}, 500

      {:ok, second} = Social.add_friend(@pubkey, "Two")
      assert first.id == second.id
      assert second.name_override == "One"
      refute_receive {:friend_added, _event}, 100
      refute_receive {:contact_changed, _event}, 100
      assert length(Social.list_friends()) == 1
    end

    test "the name is optional: none, or blank, is a friend without an override" do
      assert {:ok, %Contact{pubkey: @pubkey, name_override: nil}} = Social.add_friend(@pubkey)
      :ok = Social.remove_friend(@pubkey)

      assert {:ok, %Contact{pubkey: @pubkey, name_override: nil}} = Social.add_friend(@pubkey, "  ")
      assert [%Contact{name_override: nil}] = Social.list_friends()
    end

    test "rejects a bad key and your own key" do
      assert {:error, :invalid_pubkey} = Social.add_friend("npub1nope", "X")
      assert {:error, :invalid_pubkey} = Social.add_friend("12")

      Identity.ensure()
      assert {:error, :own_key} = Social.add_friend(Identity.npub(), "Me")
      assert {:error, :own_key} = Social.add_friend(Identity.npub())
      assert Social.list_friends() == []
    end
  end

  describe "set_name_override/2" do
    test "renames and broadcasts ContactChanged once per change; the same name again is silent" do
      {:ok, _friend} = Social.add_friend(@pubkey, "One")
      Social.subscribe()

      assert {:ok, %Contact{name_override: "Nick"}} = Social.set_name_override(@pubkey, " Nick ")
      assert_receive {:contact_changed, %ContactChanged{pubkey: @pubkey}}, 500

      assert {:ok, %Contact{name_override: "Nick"}} = Social.set_name_override(@pubkey, "Nick")
      refute_receive {:contact_changed, _event}, 100
    end

    test "a blank clears the override and broadcasts; nil on none is silent" do
      {:ok, _friend} = Social.add_friend(@pubkey, "One")
      Social.subscribe()

      assert {:ok, %Contact{name_override: nil}} = Social.set_name_override(@pubkey, "")
      assert_receive {:contact_changed, %ContactChanged{pubkey: @pubkey}}, 500
      assert Social.contact_by_pubkey(@pubkey).name_override == nil

      assert {:ok, %Contact{name_override: nil}} = Social.set_name_override(@pubkey, nil)
      assert {:ok, %Contact{name_override: nil}} = Social.set_name_override(@pubkey, "   ")
      refute_receive {:contact_changed, _event}, 100
    end

    test "refuses a key not on the roster" do
      assert {:error, :not_a_contact} = Social.set_name_override(String.duplicate("a", 64), "X")
    end
  end

  describe "set_show_avatar/2" do
    test "flips the switch and broadcasts ContactChanged once per change; an unknown key is refused" do
      {:ok, %Contact{show_avatar: true}} = Social.add_friend(@pubkey, "One")
      Social.subscribe()

      assert {:ok, %Contact{show_avatar: false}} = Social.set_show_avatar(@pubkey, false)
      assert_receive {:contact_changed, %ContactChanged{pubkey: @pubkey}}, 500
      assert {:ok, %Contact{show_avatar: false}} = Social.set_show_avatar(@pubkey, false)
      refute_receive {:contact_changed, _event}, 100
      assert {:error, :not_a_contact} = Social.set_show_avatar(String.duplicate("a", 64), true)
    end
  end

  describe "set_hue_override/2" do
    test "sets the reader's hue, clears it with nil, broadcasts once per change; a bad hue or key is refused" do
      {:ok, %Contact{hue_override: nil}} = Social.add_friend(@pubkey, "One")
      Social.subscribe()

      assert {:ok, %Contact{hue_override: 195}} = Social.set_hue_override(@pubkey, 195)
      assert_receive {:contact_changed, %ContactChanged{pubkey: @pubkey}}, 500
      assert {:ok, %Contact{hue_override: 195}} = Social.set_hue_override(@pubkey, 195)
      refute_receive {:contact_changed, _event}, 100

      assert {:ok, %Contact{hue_override: nil}} = Social.set_hue_override(@pubkey, nil)
      assert_receive {:contact_changed, %ContactChanged{pubkey: @pubkey}}, 500

      assert {:error, :invalid_hue} = Social.set_hue_override(@pubkey, 360)
      assert {:error, :not_a_contact} = Social.set_hue_override(String.duplicate("a", 64), 12)
    end
  end

  describe "remove_friend/1" do
    test "removes by pubkey and broadcasts; absent is a no-op" do
      {:ok, _friend} = Social.add_friend(@pubkey, "Sample Friend")
      Social.subscribe()

      assert :ok = Social.remove_friend(@pubkey)
      assert_receive {:friend_removed, %FriendRemoved{pubkey: @pubkey}}, 500
      assert Social.list_friends() == []

      assert :ok = Social.remove_friend(@pubkey)
      refute_receive {:friend_removed, _event}, 100
    end
  end

  describe "followed_key?/1" do
    test "the identity, every friend and every member of a members-rule relay are followed; anything else is not" do
      refute Social.followed_key?(@pubkey)

      {:ok, _friend} = Social.add_friend(@pubkey, "Sample Friend")
      assert Social.followed_key?(String.upcase(@pubkey))
      :ok = Social.remove_friend(@pubkey)
      refute Social.followed_key?(@pubkey)

      {:ok, _relay} = Social.add_relay("wss://group.example", :members)
      :ok = Social.note_member("wss://group.example", @pubkey)
      assert Social.followed_key?(@pubkey)

      {:ok, _relay} = Social.set_follow("wss://group.example", :added)
      refute Social.followed_key?(@pubkey)

      Identity.ensure()
      assert Social.followed_key?(Identity.pubkey())
    end
  end

  describe "a member and a friend are one contact" do
    setup do
      {:ok, _relay} = Social.add_relay("wss://group.example", :members)
      :ok = Social.note_member("wss://group.example", @pubkey)
      :ok
    end

    test "adding a member as a friend promotes the row, keeping its overrides, and broadcasts FriendAdded" do
      {:ok, _contact} = Social.set_name_override(@pubkey, "Nick")
      Social.subscribe()

      assert {:ok, %Contact{added_at: %DateTime{}, name_override: "Nick"}} = Social.add_friend(@pubkey)
      assert_receive {:friend_added, %FriendAdded{pubkey: @pubkey}}, 500
      assert [%Contact{pubkey: @pubkey}] = Social.list_friends()

      assert {:ok, %Contact{name_override: "Nick"}} = Social.add_friend(@pubkey, "Given")
      refute_receive {:friend_added, _event}, 100
    end

    test "removing a friend who is still a member keeps the row and the profile; the key stays followed" do
      {:ok, _contact} = Social.add_friend(@pubkey, "Sample Friend")
      {:ok, _profile} = Social.ingest_profile(profile_event("Published"))
      Social.subscribe()

      assert :ok = Social.remove_friend(@pubkey)
      assert_receive {:friend_removed, %FriendRemoved{pubkey: @pubkey}}, 500
      assert Social.list_friends() == []
      assert Social.followed_key?(@pubkey)
      assert %{@pubkey => %Person{published_name: "Published", friend?: false}} = Social.people()
    end

    test "a removed friend's choices wait for a return" do
      {:ok, _relay} = Social.add_relay("wss://relay.example")
      other = "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
      {:ok, _friend} = Social.add_friend(other, "Sample Friend")
      {:ok, _contact} = Social.set_hidden(other, true)

      :ok = Social.remove_friend(other)
      refute Social.followed_key?(other)
      refute Map.has_key?(Social.people(), other)

      {:ok, %Contact{hidden: true, name_override: "Sample Friend"}} = Social.add_friend(other)
      assert %{^other => %Person{hidden: true}} = Social.people()
    end

    test "removing a friend from the roster as a member only is a no-op" do
      Social.subscribe()
      assert :ok = Social.remove_friend(@pubkey)
      refute_receive {:friend_removed, _event}, 100
      assert Social.followed_key?(@pubkey)
    end
  end

  describe "set_hidden/2" do
    test "hides and shows, broadcasting ContactChanged once per flip; an unknown key is refused" do
      {:ok, _contact} = Social.add_friend(@pubkey, "Sample Friend")
      Social.subscribe()

      assert {:ok, %Contact{hidden: true}} = Social.set_hidden(@pubkey, true)
      assert_receive {:contact_changed, %ContactChanged{pubkey: @pubkey}}, 500
      assert %{@pubkey => %Person{hidden: true}} = Social.people()

      assert {:ok, %Contact{hidden: true}} = Social.set_hidden(@pubkey, true)
      refute_receive {:contact_changed, _event}, 100

      assert {:ok, %Contact{hidden: false}} = Social.set_hidden(@pubkey, false)
      assert {:error, :not_a_contact} = Social.set_hidden(String.duplicate("a", 64), true)
    end
  end
end
