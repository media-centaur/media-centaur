defmodule MediaCentaur.Social.FriendTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Events.FriendAdded
  alias MediaCentaur.Social.Events.FriendChanged
  alias MediaCentaur.Social.Events.FriendRemoved
  alias MediaCentaur.Social.Friend
  alias MediaCentaur.Social.Identity

  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  describe "add_friend/2" do
    test "accepts an npub, stores lowercase hex and the trimmed name, broadcasts" do
      Social.subscribe()
      npub = Keys.to_npub(@pubkey)

      assert {:ok, %Friend{pubkey: @pubkey, name_override: "Sample Friend"}} =
               Social.add_friend(npub, "  Sample Friend ")

      assert_receive {:friend_added, %FriendAdded{pubkey: @pubkey}}, 500
      assert [%Friend{pubkey: @pubkey}] = Social.list_friends()
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
      refute_receive {:friend_changed, _event}, 100
      assert length(Social.list_friends()) == 1
    end

    test "rejects a bad key, a blank name, and your own key" do
      assert {:error, :invalid_pubkey} = Social.add_friend("npub1nope", "X")
      assert {:error, :invalid_pubkey} = Social.add_friend("12", "X")
      assert {:error, :name_required} = Social.add_friend(@pubkey, "   ")

      Identity.ensure()
      assert {:error, :own_key} = Social.add_friend(Identity.npub(), "Me")
      assert Social.list_friends() == []
    end
  end

  describe "set_name_override/2" do
    test "renames and broadcasts FriendChanged once per change; the same name again is silent" do
      {:ok, _friend} = Social.add_friend(@pubkey, "One")
      Social.subscribe()

      assert {:ok, %Friend{name_override: "Nick"}} = Social.set_name_override(@pubkey, " Nick ")
      assert_receive {:friend_changed, %FriendChanged{pubkey: @pubkey}}, 500

      assert {:ok, %Friend{name_override: "Nick"}} = Social.set_name_override(@pubkey, "Nick")
      refute_receive {:friend_changed, _event}, 100
    end

    test "refuses a blank name and a key not on the roster" do
      {:ok, _friend} = Social.add_friend(@pubkey, "One")

      assert {:error, :name_required} = Social.set_name_override(@pubkey, "   ")
      assert Social.friend_by_pubkey(@pubkey).name_override == "One"
      assert {:error, :not_a_friend} = Social.set_name_override(String.duplicate("a", 64), "X")
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
end
