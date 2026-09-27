defmodule MediaCentaur.Social.AvatarStoreTest do
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Social.AvatarStore

  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @webp <<"RIFF", 0, 0, 0, 0, "WEBPVP8 ", 0, 0, 0, 0>>

  # The store lives under `{data_dir}/images/social/`: point data_dir at a
  # per-test tmp dir (GlobalStateSandbox restores the config term).
  setup do
    dir = Path.join(System.tmp_dir!(), "avatar-store-#{System.unique_integer([:positive])}")
    config = :persistent_term.get({Config, :config})
    :persistent_term.put({Config, :config}, Map.put(config, :data_dir, dir))
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "writes the bytes under images/social by key and type, and reads them back", %{dir: dir} do
    assert :ok = AvatarStore.write(@pubkey, "image/webp", @webp)
    assert File.read!(Path.join(dir, "images/social/#{@pubkey}.webp")) == @webp
    assert AvatarStore.read(@pubkey, "image/webp") == {:ok, @webp}
  end

  test "the URL is versioned and nil when no file exists" do
    assert AvatarStore.url(@pubkey, "image/webp", 1_700_000_000) == nil
    :ok = AvatarStore.write(@pubkey, "image/webp", @webp)

    assert AvatarStore.url(@pubkey, "image/webp", 1_700_000_000) ==
             "/media-images/images/social/#{@pubkey}.webp?v=1700000000"

    assert AvatarStore.url(@pubkey, nil, 1_700_000_000) == nil
  end

  test "a new type replaces the old file; delete removes every file for the key", %{dir: dir} do
    :ok = AvatarStore.write(@pubkey, "image/webp", @webp)
    :ok = AvatarStore.write(@pubkey, "image/png", <<0x89, "PNG">>)
    assert File.ls!(Path.join(dir, "images/social")) == ["#{@pubkey}.png"]
    :ok = AvatarStore.delete(@pubkey)
    assert File.ls!(Path.join(dir, "images/social")) == []
    assert :ok = AvatarStore.delete(@pubkey)
  end
end
