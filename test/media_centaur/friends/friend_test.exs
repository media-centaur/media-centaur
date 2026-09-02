defmodule MediaCentaur.Friends.FriendTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Events.FriendAdded
  alias MediaCentaur.Friends.Events.FriendRemoved
  alias MediaCentaur.Friends.Friend
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Nostr.Keys

  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  describe "add_friend/2" do
    test "accepts an npub, stores lowercase hex + trimmed nickname, broadcasts" do
      Friends.subscribe()
      npub = Keys.to_npub(@pubkey)

      assert {:ok, %Friend{pubkey: @pubkey, nickname: "Sample Friend"}} =
               Friends.add_friend(npub, "  Sample Friend ")

      assert_receive {:friend_added, %FriendAdded{pubkey: @pubkey}}, 500
      assert [%Friend{pubkey: @pubkey}] = Friends.list_friends()
      assert Friends.friend_pubkeys() == [@pubkey]
    end

    test "accepts hex in any case and re-adding updates the nickname" do
      {:ok, first} = Friends.add_friend(String.upcase(@pubkey), "One")
      {:ok, second} = Friends.add_friend(@pubkey, "Two")

      assert first.id == second.id
      assert Friends.friend_by_pubkey(@pubkey).nickname == "Two"
      assert length(Friends.list_friends()) == 1
    end

    test "rejects a bad key, a blank nickname, and your own key" do
      assert {:error, :invalid_pubkey} = Friends.add_friend("npub1nope", "X")
      assert {:error, :invalid_pubkey} = Friends.add_friend("12", "X")
      assert {:error, :nickname_required} = Friends.add_friend(@pubkey, "   ")

      Identity.ensure()
      assert {:error, :own_key} = Friends.add_friend(Identity.npub(), "Me")
      assert Friends.list_friends() == []
    end
  end

  describe "remove_friend/1" do
    test "removes by pubkey and broadcasts; absent is a no-op" do
      {:ok, _friend} = Friends.add_friend(@pubkey, "Sample Friend")
      Friends.subscribe()

      assert :ok = Friends.remove_friend(@pubkey)
      assert_receive {:friend_removed, %FriendRemoved{pubkey: @pubkey}}, 500
      assert Friends.list_friends() == []

      assert :ok = Friends.remove_friend(@pubkey)
      refute_receive {:friend_removed, _event}, 100
    end
  end
end
