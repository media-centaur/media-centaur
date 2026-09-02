defmodule MediaCentaur.Social.FriendTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Events.FriendAdded
  alias MediaCentaur.Social.Events.FriendRemoved
  alias MediaCentaur.Social.Friend
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Nostr.Keys

  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  describe "add_friend/2" do
    test "accepts an npub, stores lowercase hex + trimmed nickname, broadcasts" do
      Social.subscribe()
      npub = Keys.to_npub(@pubkey)

      assert {:ok, %Friend{pubkey: @pubkey, nickname: "Sample Friend"}} =
               Social.add_friend(npub, "  Sample Friend ")

      assert_receive {:friend_added, %FriendAdded{pubkey: @pubkey}}, 500
      assert [%Friend{pubkey: @pubkey}] = Social.list_friends()
      assert Social.friend_pubkeys() == [@pubkey]
    end

    test "accepts hex in any case and re-adding updates the nickname" do
      {:ok, first} = Social.add_friend(String.upcase(@pubkey), "One")
      {:ok, second} = Social.add_friend(@pubkey, "Two")

      assert first.id == second.id
      assert Social.friend_by_pubkey(@pubkey).nickname == "Two"
      assert length(Social.list_friends()) == 1
    end

    test "renaming an existing friend broadcasts; an identical re-add stays silent" do
      Social.subscribe()

      {:ok, _friend} = Social.add_friend(@pubkey, "One")
      assert_receive {:friend_added, %FriendAdded{pubkey: @pubkey}}, 500

      {:ok, _friend} = Social.add_friend(@pubkey, "Two")
      assert_receive {:friend_added, %FriendAdded{pubkey: @pubkey}}, 500

      {:ok, _friend} = Social.add_friend(@pubkey, "Two")
      refute_receive {:friend_added, _event}, 100
    end

    test "rejects a bad key, a blank nickname, and your own key" do
      assert {:error, :invalid_pubkey} = Social.add_friend("npub1nope", "X")
      assert {:error, :invalid_pubkey} = Social.add_friend("12", "X")
      assert {:error, :nickname_required} = Social.add_friend(@pubkey, "   ")

      Identity.ensure()
      assert {:error, :own_key} = Social.add_friend(Identity.npub(), "Me")
      assert Social.list_friends() == []
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
