defmodule MediaCentaur.Social.ProfileTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmpDataDir

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Social
  alias MediaCentaur.Social.AvatarStore
  alias MediaCentaur.Social.Events.ProfileUpdated
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Profile
  alias MediaCentaur.Social.Profile.Translation

  @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @friend_pubkey Keys.pubkey(@friend_secret)

  # Avatars are written under `{data_dir}/images/social/`.
  setup :setup_tmp_data_dir

  defp friend_profile(name, created_at),
    do: Event.sign(Translation.to_event(%{name: name}, @friend_pubkey, created_at), @friend_secret)

  describe "save_profile/2" do
    test "mints the identity, stores the row, publishes, broadcasts; a blank name is refused" do
      refute Identity.present?()
      Social.subscribe()

      assert {:error, :name_required} = Social.save_profile("   ", :keep)
      assert {:error, :name_too_long} = Social.save_profile(String.duplicate("x", 51), :keep)
      refute Identity.present?()

      assert {:ok, %Profile{name: "Sample Name", created_at: first}} =
               Social.save_profile("  Sample Name ", :keep)

      assert Identity.present?()
      me = Identity.pubkey()
      assert_receive {:profile_updated, %ProfileUpdated{pubkey: ^me}}, 500
      assert %Profile{name: "Sample Name"} = Social.own_profile()

      # A second save within the same second is stamped strictly after the first.
      assert {:ok, %Profile{name: "Renamed", created_at: second}} = Social.save_profile("Renamed", :keep)
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

    test "a friend's hue is stored with the profile; a newer profile without one clears it" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")

      {:ok, %Profile{hue: 195}} =
        Social.ingest_profile(
          Event.sign(
            Translation.to_event(%{name: "One", hue: 195}, @friend_pubkey, 1_700_000_000),
            @friend_secret
          )
        )

      {:ok, %Profile{hue: nil}} =
        Social.ingest_profile(
          Event.sign(Translation.to_event(%{name: "One"}, @friend_pubkey, 1_700_000_001), @friend_secret)
        )
    end
  end

  describe "pruning" do
    test "removing a friend removes their profile; replacing the identity removes the old own row" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")
      {:ok, _profile} = Social.ingest_profile(friend_profile("One", 1_700_000_000))
      :ok = Social.remove_friend(@friend_pubkey)
      assert Social.people() == %{}
      assert Repo.all(Profile) == []

      {:ok, _profile} = Social.save_profile("Me", :keep)
      old = Identity.pubkey()
      :ok = Social.import_identity(Keys.to_nsec(Secret.wrap(String.duplicate("0", 63) <> "5")))
      refute Identity.pubkey() == old
      assert Repo.all(Profile) == []
      assert Social.own_profile() == nil
    end

    test "re-importing the same key keeps the own profile" do
      {:ok, _profile} = Social.save_profile("Me", :keep)
      :ok = Social.import_identity(Identity.export_nsec())

      assert %Profile{name: "Me"} = Social.own_profile()
    end
  end

  describe "avatars" do
    @webp <<"RIFF", 0, 0, 0, 0, "WEBPVP8 ", 0, 0, 0, 0>>

    test "save_profile/2 sets, keeps and removes the avatar; the event carries it and the file follows" do
      {:ok, %Profile{avatar_type: "image/webp"}} = Social.save_profile("Me", {:new, @webp})
      me = Identity.pubkey()
      assert {:ok, @webp} = AvatarStore.read(me, "image/webp")
      [event] = Social.own_events()
      assert %{"avatar" => %{"type" => "image/webp"}} = Jason.decode!(event.content)
      assert Social.own_person().avatar_url =~ "images/social/#{me}.webp?v="

      {:ok, %Profile{name: "Renamed", avatar_type: "image/webp"}} = Social.save_profile("Renamed", :keep)
      [kept] = Social.own_events()
      assert %{"avatar" => %{"type" => "image/webp"}} = Jason.decode!(kept.content)

      {:ok, %Profile{avatar_type: nil}} = Social.save_profile("Renamed", :none)
      assert AvatarStore.read(me, "image/webp") == {:error, :enoent}
      assert Social.own_person().avatar_url == nil
      refute Map.has_key?(Jason.decode!(hd(Social.own_events()).content), "avatar")
    end

    test "ingest_profile/1 writes a friend's avatar, replaces it, and removes it when a newer profile has none" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")

      with_avatar =
        Event.sign(
          Translation.to_event(
            %{name: "One", avatar: %{type: "image/webp", bytes: @webp}},
            @friend_pubkey,
            1_700_000_000
          ),
          @friend_secret
        )

      assert {:ok, %Profile{avatar_type: "image/webp"}} = Social.ingest_profile(with_avatar)
      assert {:ok, @webp} = AvatarStore.read(@friend_pubkey, "image/webp")
      assert Social.people()[@friend_pubkey].avatar_url =~ ".webp?v=1700000000"

      png = <<0x89, "PNG\r\n", 0x1A, 0x0A, 0, 0>>

      replaced =
        Event.sign(
          Translation.to_event(
            %{name: "One", avatar: %{type: "image/png", bytes: png}},
            @friend_pubkey,
            1_700_000_001
          ),
          @friend_secret
        )

      assert {:ok, %Profile{avatar_type: "image/png"}} = Social.ingest_profile(replaced)
      assert {:ok, ^png} = AvatarStore.read(@friend_pubkey, "image/png")
      assert AvatarStore.read(@friend_pubkey, "image/webp") == {:error, :enoent}
      assert Social.people()[@friend_pubkey].avatar_url =~ ".png?v=1700000001"

      without =
        Event.sign(Translation.to_event(%{name: "One"}, @friend_pubkey, 1_700_000_002), @friend_secret)

      assert {:ok, %Profile{avatar_type: nil}} = Social.ingest_profile(without)
      assert AvatarStore.read(@friend_pubkey, "image/png") == {:error, :enoent}
      assert Social.people()[@friend_pubkey].avatar_url == nil
    end

    test "save_profile/2 refuses new bytes over the cap before minting anything" do
      over = :binary.copy(<<0>>, Translation.max_avatar_bytes() + 1)
      assert {:error, :avatar_too_large} = Social.save_profile("Me", {:new, over})
      refute Identity.present?()
      assert Social.own_events() == []
    end

    test "save_profile/2 with :keep and a missing file publishes no avatar, and the row follows" do
      {:ok, %Profile{avatar_type: "image/webp"}} = Social.save_profile("Me", {:new, @webp})
      :ok = AvatarStore.delete(Identity.pubkey())

      assert {:ok, %Profile{avatar_type: nil}} = Social.save_profile("Me", :keep)
      refute Map.has_key?(Jason.decode!(hd(Social.own_events()).content), "avatar")
    end

    test "removing the friend removes the file" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")

      {:ok, _} =
        Social.ingest_profile(
          Event.sign(
            Translation.to_event(
              %{name: "One", avatar: %{type: "image/webp", bytes: @webp}},
              @friend_pubkey,
              1
            ),
            @friend_secret
          )
        )

      :ok = Social.remove_friend(@friend_pubkey)
      assert AvatarStore.read(@friend_pubkey, "image/webp") == {:error, :enoent}
    end

    test "replacing the identity removes the old key's file; re-importing the same key keeps it" do
      {:ok, _profile} = Social.save_profile("Me", {:new, @webp})
      old = Identity.pubkey()

      :ok = Social.import_identity(Identity.export_nsec())
      assert {:ok, @webp} = AvatarStore.read(old, "image/webp")

      :ok = Social.import_identity(Keys.to_nsec(Secret.wrap(String.duplicate("0", 63) <> "5")))
      assert AvatarStore.read(old, "image/webp") == {:error, :enoent}
    end
  end

  test "own_event_kind/1 names the own profile and nothing else" do
    {:ok, _profile} = Social.save_profile("Me", :keep)
    [event] = Social.own_events()
    assert Social.own_event_kind(event.id) == :profile
    assert Social.own_event_kind("nope") == nil
  end
end
