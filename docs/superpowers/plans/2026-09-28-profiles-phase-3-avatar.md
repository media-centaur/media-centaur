# Profiles, phase 3: the avatar. Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person chooses a picture; friends see it in every identity tile, unless they switch it off for that friend.

**Architecture:** The avatar is a field of the profile (ADR-073): WebP, JPEG or PNG bytes inline in the kind 12160 content, decoded size capped, signature bytes checked, never decoded by a reader. `Social.Profile` gains `avatar_type`; `Social.AvatarStore` writes the bytes to `{data_dir}/images/social/<pubkey>.<ext>` and mints the versioned URL the image server already serves; `ImageFiles.square_webp/2` is the sender's 256×256 master; `Social.save_profile/2` keeps, removes or sets the avatar; `ingest_profile/1` writes the file; pruning removes it; `Friend.show_avatar` and `Social.set_show_avatar/2` give the reader the switch; `Person.avatar_url` is nil when hidden or absent. The Settings profile card gains the app's first LiveView upload; the card's foot gains the switch. Two path helpers move into `ImageFiles` so the three data-dir image stores share one derivation.

**Tech Stack:** Elixir 1.20 / Phoenix LiveView 1.2 uploads, Ecto + `ecto_sqlite3`, `image` 0.72 (libvips), Phoenix Storybook, ExUnit + LazyHTML.

**Design:** `docs/superpowers/specs/2026-09-27-profiles-design.md` §§ On the wire (avatar), Storage (avatar file), The web reads a Person, Settings → Social, Friends, Errors. ADR-073, UIDR-047. Campaign `campaigns/profiles.md` § Follow-ups (phase 3 items). Unify pass 2026-09-28 (in the campaign's decisions): one path derivation for the data-dir image stores; no `avatar_path` column; URLs without `?w=`.

---

## Read before starting

- **Never run `mix` directly.** Every command is `~/scripts/agents/agent-mix …`. The dev daily driver compiles into this checkout's `_build/dev`.
- **Test first**, red then green, per task. The suite stays green at every commit in this phase.
- Work on `main`, commit per task, push nothing. The relay needs no change: the avatar rides inside kind 12160's content.
- **Commit messages**: conventional, plain prose, the harness's attribution trailer, never `Co-Authored-By`.
- **Copy**: the profile card's avatar labels and the switch's words go through the `writing-copy` skill. Working strings are given.
- **Storybook**: MC0009; the person card story gains the switch's two states; the identity tile's avatar variations already exist.
- **Zero warnings; `mix_unused`**: every function added gains a caller in this phase.
- **Tests and the data dir**: tests that write files set a per-test data dir the way `test/media_centaur/tmdb_artwork_test.exs:11-19` does (`:persistent_term.put({Config, :config}, Map.put(config, :data_dir, dir))` with `on_exit(File.rm_rf!)`), or use `TmdbStubs.setup_artwork_cache/1`. Images for tests are generated with `Image.new/3` and written with `Image.write/3`, as `test/media_centaur/image_files_test.exs` does; there are no binary fixtures.
- **Wire caps live once**: `Social.Profile.Translation`. The protocol page (Task 8) mirrors them.

## What this phase does not do, on purpose

- No avatar on the Feed row beyond the tile (the tile is the one drawing of a person).
- No cropping UI; the master is a centre crop.
- No boot-time heal for a missing file; the URL is nil until the next profile arrives (spec § Errors).
- No global hide-all-avatars setting.
- `nickname` is not dropped; the release after phase 2's ship drops it.

## File structure

Created:

- `priv/repo/migrations/20260928120000_profiles_carry_an_avatar_type.exs`, `priv/repo/migrations/20260928121000_friends_show_avatar.exs`
- `lib/media_centaur/social/avatar_store.ex`
- `test/media_centaur/social/avatar_store_test.exs`

Modified: `lib/media_centaur/image_files.ex` (+ `on_disk_path/1`, `web_path/2`, `square_webp/2`), `lib/media_centaur/apps/artwork.ex`, `lib/media_centaur/tmdb_artwork.ex`, `lib/media_centaur_web/plugs/image_server.ex` (a comment), `lib/media_centaur/social/profile.ex`, `lib/media_centaur/social/profile/translation.ex`, `lib/media_centaur/social/friend.ex`, `lib/media_centaur/social/person.ex`, `lib/media_centaur/social.ex`, `lib/media_centaur_web/live/settings_live.ex`, `lib/media_centaur_web/live/settings_live/social_section.ex`, `lib/media_centaur_web/live/discovery_live.ex`, `lib/media_centaur_web/components/discovery/person_card.ex`, `lib/media_centaur_web/components/discovery/identity_tile.ex` (moduledoc only), `storybook/discovery/person_card.story.exs`, `test/support/discovery_rows.ex`, tests per task, `docs/social-protocol.md`, `docs/social.md`, `docs/architecture.md`, `docs/GLOSSARY.md`, `campaigns/profiles.md`, the spec, wiki pages.

---

### Task 1: One derivation of a data-dir image path; the sender's master

**Files:**
- Modify: `lib/media_centaur/image_files.ex`, `lib/media_centaur/apps/artwork.ex`, `lib/media_centaur/tmdb_artwork.ex`, `lib/media_centaur_web/plugs/image_server.ex:98-99`
- Test: `test/media_centaur/image_files_test.exs`

- [ ] **Step 1: Tests**

In `test/media_centaur/image_files_test.exs` add (the file uses `@moduletag :tmp_dir` and generates images with `Image.new/3`):

```elixir
  describe "on_disk_path/1 and web_path/2" do
    test "an app-owned relative path lives under the data dir and is served with a version" do
      assert ImageFiles.on_disk_path("images/social/abc.webp") ==
               Path.join(MediaCentaur.Settings.Config.get(:data_dir), "images/social/abc.webp")

      assert ImageFiles.web_path("images/social/abc.webp", 1_700_000_000) ==
               "/media-images/images/social/abc.webp?v=1700000000"
    end
  end

  describe "square_webp/2" do
    test "centre-crops any image to a square WebP of the given side, in memory", %{tmp_dir: dir} do
      source = Path.join(dir, "wide.png")
      {:ok, img} = Image.new(400, 300, color: :red)
      {:ok, _} = Image.write(img, source)

      assert {:ok, bytes} = ImageFiles.square_webp(source, 256)
      assert <<"RIFF", _size::32-little, "WEBP", _rest::binary>> = bytes
      {:ok, back} = Image.from_binary(bytes)
      assert {256, 256, _bands} = Image.shape(back)
    end

    test "a file that is not an image is refused" do
      assert {:error, _reason} = ImageFiles.square_webp(__ENV__.file, 256)
    end
  end
```

Run: `~/scripts/agents/agent-mix test test/media_centaur/image_files_test.exs`. Expected: red (three undefined functions).

- [ ] **Step 2: `ImageFiles`**

Add after `web_path/1`:

```elixir
  @doc "`web_path/1` with the immutable-cache version `ImageServer` honours: a replaced master mints a new URL."
  @spec web_path(String.t(), non_neg_integer()) :: String.t()
  def web_path(relative_path, version) when is_binary(relative_path) and is_integer(version),
    do: web_path(relative_path) <> "?v=#{version}"

  @doc """
  The on-disk path of an app-owned image under the data dir: what
  `ImageServer` opens for `web_path/1` of the same relative path when no
  media directory holds it. The one derivation the data-dir stores
  share (`TmdbArtwork`, `Apps.Artwork`, `Social.AvatarStore`).
  """
  @spec on_disk_path(String.t()) :: String.t()
  def on_disk_path(relative_path) when is_binary(relative_path),
    do: Path.join(Config.get(:data_dir) || "data", relative_path)
```

(`Config` is `MediaCentaur.Settings.Config`; alias it if the module does not already.) Add after `download_raw/3`:

```elixir
  @doc """
  A square WebP master of `side` pixels from the image file at `path`,
  centre-cropped, returned in memory: the avatar a sender publishes.
  `{:error, reason}` when the file is not an image libvips can open.
  """
  @spec square_webp(Path.t(), pos_integer()) :: {:ok, binary()} | {:error, term()}
  def square_webp(path, side) when is_binary(path) and is_integer(side) and side > 0 do
    with {:ok, image} <- Image.open(path),
         {:ok, square} <- Image.thumbnail(image, side, crop: :center) do
      Image.write(square, :memory, suffix: ".webp", quality: 82)
    end
  end
```

- [ ] **Step 3: The two stores adopt the helpers**

`lib/media_centaur/apps/artwork.ex`: `on_disk_path/2` becomes `ImageFiles.on_disk_path(relative_path(role, app_id))`; `delete/1`'s `dir` becomes `ImageFiles.on_disk_path(Path.join(@subdir, app_id))`; `role_url/2` uses `ImageFiles.web_path(relative_path(role, app_id), version)`; delete the private `data_dir/0` and the `Config` alias if unused. `lib/media_centaur/tmdb_artwork.ex`: `on_disk_path/3` uses `ImageFiles.on_disk_path/1`; keep its `root/0` if other code needs the directory root (read it; if `root/0` is only `data_dir <> @subdir`, express it through the helper too). `lib/media_centaur_web/plugs/image_server.ex:98-99`: replace the `ReleaseTracking.ImageStore` mention with `Apps.Artwork` and `Social.AvatarStore`.

Run: `~/scripts/agents/agent-mix test test/media_centaur/image_files_test.exs test/media_centaur/apps test/media_centaur/tmdb_artwork_test.exs test/media_centaur_web/plugs/image_server_test.exs`. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/media_centaur/image_files.ex lib/media_centaur/apps/artwork.ex lib/media_centaur/tmdb_artwork.ex lib/media_centaur_web/plugs/image_server.ex test/media_centaur/image_files_test.exs
git commit -m "refactor: ImageFiles owns the data-dir path and the versioned URL; square_webp is the avatar master"
```

---

### Task 2: The avatar on the wire and in the row

**Files:**
- Create: `priv/repo/migrations/20260928120000_profiles_carry_an_avatar_type.exs`
- Modify: `lib/media_centaur/social/profile.ex`, `lib/media_centaur/social/profile/translation.ex`
- Test: `test/media_centaur/social/profile_translation_test.exs`

- [ ] **Step 1: Tests**

In `profile_translation_test.exs` add helpers and tests:

```elixir
  @webp <<"RIFF", 0, 0, 0, 0, "WEBPVP8 ", 0, 0, 0, 0>>
  @png <<0x89, "PNG\r\n", 0x1A, 0x0A, 0, 0, 0, 0>>
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0>>

  defp avatar_json(type, bytes), do: Jason.encode!(%{"type" => type, "data" => Base.encode64(bytes)})

  test "to_event/4 carries the avatar as base64 with its type; nil leaves it off" do
    event = Translation.to_event("Sample Name", %{type: "image/webp", bytes: @webp}, @pubkey, 1)
    assert %{"avatar" => %{"type" => "image/webp", "data" => data}} = Jason.decode!(event.content)
    assert Base.decode64!(data) == @webp
    refute Map.has_key?(Jason.decode!(Translation.to_event("x", nil, @pubkey, 1).content), "avatar")
  end

  test "from_event/1 reads a well-formed avatar of each type and hands the bytes on undecoded" do
    for {type, bytes} <- [{"image/webp", @webp}, {"image/png", @png}, {"image/jpeg", @jpeg}] do
      content = ~s({"v":1,"name":"x","avatar":#{avatar_json(type, bytes)}})
      assert {:ok, %{avatar_type: ^type, avatar_bytes: ^bytes}} = Translation.from_event(signed(content))
    end

    assert {:ok, %{avatar_type: nil, avatar_bytes: nil}} = Translation.from_event(signed(~s({"v":1,"name":"x"})))
  end

  test "a malformed avatar drops the whole profile: unknown type, bad base64, over the cap, signature mismatch, wrong shape" do
    bad = [
      ~s({"v":1,"avatar":#{avatar_json("image/gif", @png)}}),
      ~s({"v":1,"avatar":{"type":"image/png","data":"@@@"}}),
      ~s({"v":1,"avatar":#{avatar_json("image/png", @png <> :binary.copy(<<0>>, 64 * 1024))}}),
      ~s({"v":1,"avatar":#{avatar_json("image/png", @webp)}}),
      ~s({"v":1,"avatar":"not an object"}),
      ~s({"v":1,"avatar":{"type":"image/png"}})
    ]

    for content <- bad do
      assert {:error, :bad_content} = Translation.from_event(signed(content)), content
    end
  end

  test "the decoded cap is 64 KB inclusive" do
    at_cap = @png <> :binary.copy(<<0>>, 64 * 1024 - byte_size(@png))
    assert {:ok, %{avatar_bytes: ^at_cap}} = Translation.from_event(signed(~s({"v":1,"avatar":#{avatar_json("image/png", at_cap)}})))
  end
```

Update the existing `to_event/3` calls in this file and in `profile_test.exs` and `relay_sync_test.exs` to `to_event(name, nil, pubkey, created_at)`. Run: red.

- [ ] **Step 2: Migration**

```elixir
defmodule MediaCentaur.Repo.Migrations.ProfilesCarryAnAvatarType do
  @moduledoc "A profile's avatar type (`image/webp`, `image/jpeg`, `image/png`), nil when the key published none; the file's path derives from the key and the type (`Social.AvatarStore`)."
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :avatar_type, :text
    end
  end
end
```

- [ ] **Step 3: Schema and translation**

`profile.ex`: `field :avatar_type, :string`; cast it; moduledoc: "and its avatar's type, the bytes living in `AvatarStore`'s file".

`translation.ex`: constants and readers.

```elixir
  @avatar_types %{
    "image/webp" => {"webp", <<"RIFF">>, 8, <<"WEBP">>},
    "image/png" => {"png", <<0x89, "PNG\r\n", 0x1A, 0x0A>>, 0, <<>>},
    "image/jpeg" => {"jpg", <<0xFF, 0xD8, 0xFF>>, 0, <<>>}
  }
  @max_avatar_bytes 64 * 1024

  @type avatar :: %{type: String.t(), bytes: binary()}
  @type attrs :: %{
          pubkey: String.t(),
          name: String.t() | nil,
          avatar_type: String.t() | nil,
          avatar_bytes: binary() | nil,
          raw_event: map(),
          created_at: non_neg_integer()
        }

  @doc "The avatar types a reader accepts, and the file extension for each."
  @spec avatar_extension(String.t()) :: String.t()
  def avatar_extension(type), do: @avatar_types |> Map.fetch!(type) |> elem(0)

  @doc "The decoded avatar cap in bytes; the protocol page mirrors it."
  @spec max_avatar_bytes() :: pos_integer()
  def max_avatar_bytes, do: @max_avatar_bytes
```

`to_event/4`:

```elixir
  @doc "An unsigned profile event; a nil name or avatar is left off the wire."
  @spec to_event(String.t() | nil, avatar() | nil, String.t(), non_neg_integer()) :: Event.t()
  def to_event(name, avatar, pubkey, created_at) do
    content =
      %{"v" => @content_version}
      |> put_present("name", name)
      |> put_present("avatar", avatar && %{"type" => avatar.type, "data" => Base.encode64(avatar.bytes)})

    Event.new(%{pubkey: pubkey, created_at: created_at, kind: @kind, tags: [], content: Jason.encode!(content)})
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
```

`from_event/1` gains `{:ok, avatar} <- read_avatar(content)` and puts `avatar_type: avatar && avatar.type, avatar_bytes: avatar && avatar.bytes` in the attrs. The reader:

```elixir
  # A reader never decodes an avatar: the type must be one of three, the
  # bytes must decode from base64, fit the cap and open with the type's
  # signature. Anything else drops the whole profile.
  defp read_avatar(%{"avatar" => %{"type" => type, "data" => data}}) when is_binary(type) and is_binary(data) do
    with {:ok, {_ext, magic, offset, magic2}} <- Map.fetch(@avatar_types, type),
         {:ok, bytes} <- Base.decode64(data),
         true <- byte_size(bytes) <= @max_avatar_bytes,
         true <- signature?(bytes, magic, offset, magic2) do
      {:ok, %{type: type, bytes: bytes}}
    else
      _bad -> {:error, :bad_content}
    end
  end

  defp read_avatar(%{"avatar" => nil}), do: {:ok, nil}
  defp read_avatar(%{"avatar" => _wrong_shape}), do: {:error, :bad_content}
  defp read_avatar(_absent), do: {:ok, nil}

  defp signature?(bytes, magic, offset, magic2) do
    size = byte_size(magic)
    size2 = byte_size(magic2)

    match?(<<^magic::binary-size(size), _::binary>>, bytes) and
      (size2 == 0 or match?(<<_::binary-size(offset), ^magic2::binary-size(size2), _::binary>>, bytes))
  end
```

Update the moduledoc: the avatar object, its types, the cap, the signature rule, "a reader never decodes an avatar".

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/`. Expected: PASS (Social's `save_profile` still calls `to_event/3`; fix its call to `to_event(name, nil, me, created_at)` for now, Task 3 gives it the avatar). Migrate the dev database: `~/scripts/agents/agent-mix ecto.migrate`.

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/20260928120000_profiles_carry_an_avatar_type.exs lib/media_centaur/social/profile.ex lib/media_centaur/social/profile/translation.ex lib/media_centaur/social.ex test/media_centaur/social/
git commit -m "feat: the profile carries an avatar on the wire; the reader checks type, cap and signature and never decodes it"
```

---

### Task 3: `Social.AvatarStore`, and the API keeps, removes or sets the avatar

**Files:**
- Create: `lib/media_centaur/social/avatar_store.ex`, `test/media_centaur/social/avatar_store_test.exs`
- Modify: `lib/media_centaur/social.ex` (`save_profile/2`, `ingest_profile/1`, `upsert_profile`, `delete_profile`, exports), `lib/media_centaur/social/person.ex` (moduledoc)
- Test: `test/media_centaur/social/profile_test.exs`

- [ ] **Step 1: Tests**

`avatar_store_test.exs` (set a per-test data dir as `tmdb_artwork_test.exs` does):

```elixir
defmodule MediaCentaur.Social.AvatarStoreTest do
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Settings.Config
  alias MediaCentaur.Social.AvatarStore

  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @webp <<"RIFF", 0, 0, 0, 0, "WEBPVP8 ", 0, 0, 0, 0>>

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
    assert AvatarStore.url(@pubkey, "image/webp", 1_700_000_000) == "/media-images/images/social/#{@pubkey}.webp?v=1700000000"
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
```

Check how `tmdb_artwork_test.exs` reads and restores the config term and copy that exactly (the `GlobalStateSandbox` restores it; if the term key differs, use theirs).

In `profile_test.exs` add (with the same per-test data dir in a `setup`):

```elixir
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
      with_avatar = Event.sign(Translation.to_event("One", %{type: "image/webp", bytes: @webp}, @friend_pubkey, 1_700_000_000), @friend_secret)
      assert {:ok, %Profile{avatar_type: "image/webp"}} = Social.ingest_profile(with_avatar)
      assert {:ok, @webp} = AvatarStore.read(@friend_pubkey, "image/webp")
      assert Social.people()[@friend_pubkey].avatar_url =~ ".webp?v=1700000000"

      without = Event.sign(Translation.to_event("One", nil, @friend_pubkey, 1_700_000_001), @friend_secret)
      assert {:ok, %Profile{avatar_type: nil}} = Social.ingest_profile(without)
      assert AvatarStore.read(@friend_pubkey, "image/webp") == {:error, :enoent}
      assert Social.people()[@friend_pubkey].avatar_url == nil
    end

    test "removing the friend removes the file" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")
      {:ok, _} = Social.ingest_profile(Event.sign(Translation.to_event("One", %{type: "image/webp", bytes: @webp}, @friend_pubkey, 1), @friend_secret))
      :ok = Social.remove_friend(@friend_pubkey)
      assert AvatarStore.read(@friend_pubkey, "image/webp") == {:error, :enoent}
    end
  end
```

Update every existing `Social.save_profile("…")` call in the tests to `save_profile("…", :keep)` (a first save with `:keep` and no stored avatar means none). Run: red.

- [ ] **Step 2: The store**

```elixir
defmodule MediaCentaur.Social.AvatarStore do
  @moduledoc """
  Where a known key's avatar bytes live: `{data_dir}/images/social/<pubkey>.<ext>`,
  the social instance of the data-dir artwork idiom (`TmdbArtwork`,
  `Apps.Artwork`): disk is the ledger, the URL is resolved from disk at
  read time and carries the profile's wire time as `?v=`, so a replaced
  avatar mints a new URL and an unchanged one stays immutable in the
  browser. Served by `MediaCentaurWeb.Plugs.ImageServer`; the URL never
  carries `?w=`, since a tile paints the master as it is. Written by
  `Social` when a profile is stored, removed when the profile loses its
  avatar or the key is forgotten. A reader never decodes what it stores.
  """

  alias MediaCentaur.ImageFiles
  alias MediaCentaur.Social.Profile.Translation

  @subdir "images/social"

  @doc "The data-dir-relative path for a key's avatar of `type`."
  @spec relative_path(String.t(), String.t()) :: String.t()
  def relative_path(pubkey, type), do: Path.join(@subdir, pubkey <> "." <> Translation.avatar_extension(type))

  @doc "Writes the bytes, replacing any file of another type for the key."
  @spec write(String.t(), String.t(), binary()) :: :ok
  def write(pubkey, type, bytes) when is_binary(pubkey) and is_binary(type) and is_binary(bytes) do
    :ok = delete(pubkey)
    dest = ImageFiles.on_disk_path(relative_path(pubkey, type))
    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, bytes)
  end

  @doc "The stored bytes, or `{:error, :enoent}`."
  @spec read(String.t(), String.t()) :: {:ok, binary()} | {:error, File.posix()}
  def read(pubkey, type), do: File.read(ImageFiles.on_disk_path(relative_path(pubkey, type)))

  @doc "Removes every avatar file for the key. Idempotent."
  @spec delete(String.t()) :: :ok
  def delete(pubkey) when is_binary(pubkey) do
    dir = ImageFiles.on_disk_path(@subdir)

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.starts_with?(&1, pubkey <> "."))
        |> Enum.each(&File.rm!(Path.join(dir, &1)))

      {:error, _no_dir} ->
        :ok
    end

    :ok
  end

  @doc "The versioned URL for the key's avatar, or nil when there is no type or no file."
  @spec url(String.t(), String.t() | nil, non_neg_integer()) :: String.t() | nil
  def url(_pubkey, nil, _version), do: nil

  def url(pubkey, type, version) do
    relative = relative_path(pubkey, type)
    if File.regular?(ImageFiles.on_disk_path(relative)), do: ImageFiles.web_path(relative, version)
  end
end
```

- [ ] **Step 3: The API**

In `lib/media_centaur/social.ex`: alias `MediaCentaur.Social.AvatarStore`; export `AvatarStore`. `save_profile/2`:

```elixir
  @typedoc "What the save does with the avatar: keep the stored one, remove it, or set new WebP bytes (the master `ImageFiles.square_webp/2` made)."
  @type avatar_change :: :keep | :none | {:new, binary()}

  @spec save_profile(String.t(), avatar_change()) :: {:ok, Profile.t()} | {:error, :name_required | :name_too_long}
  def save_profile(name, avatar_change) when is_binary(name) do
    with {:ok, name} <- present_name(name),
         :ok <- within_name_cap(name) do
      secret = Identity.ensure()
      me = Identity.pubkey()
      stored = Repo.get_by(Profile, pubkey: me)
      avatar = resolve_avatar(avatar_change, stored)
      created_at = Event.stamp_after(stored && stored.created_at, System.os_time(:second))
      event = name |> ProfileTranslation.to_event(avatar, me, created_at) |> Event.sign(secret)
      {:ok, attrs} = ProfileTranslation.from_event(event)
      profile = store_profile(stored, attrs)
      Connections.publish(event)
      Events.broadcast(%Events.ProfileUpdated{pubkey: me})
      {:ok, profile}
    end
  end

  defp resolve_avatar(:none, _stored), do: nil
  defp resolve_avatar({:new, bytes}, _stored), do: %{type: "image/webp", bytes: bytes}
  defp resolve_avatar(:keep, %Profile{pubkey: pubkey, avatar_type: type}) when is_binary(type) do
    case AvatarStore.read(pubkey, type) do
      {:ok, bytes} -> %{type: type, bytes: bytes}
      {:error, _missing} -> nil
    end
  end
  defp resolve_avatar(:keep, _none), do: nil
```

`ingest_profile/1`'s stored branch and `upsert_profile/2` become `store_profile/2`, which writes the row and the file together:

```elixir
  # The row and the file move together: the avatar bytes never enter
  # the row, and a profile without an avatar leaves no file behind.
  defp store_profile(stored, attrs) do
    {bytes, row_attrs} = Map.pop(attrs, :avatar_bytes)
    profile = if stored, do: Repo.update!(Profile.changeset(stored, row_attrs)), else: Repo.insert!(Profile.changeset(row_attrs))
    if bytes, do: AvatarStore.write(profile.pubkey, profile.avatar_type, bytes), else: AvatarStore.delete(profile.pubkey)
    profile
  end

  defp delete_profile(pubkey) do
    Repo.delete_all(from(profile in Profile, where: profile.pubkey == ^pubkey))
    AvatarStore.delete(pubkey)
  end
```

`people/0` and `own_person_for/2`: the join map becomes `%{pubkey => %Profile{}}`; `person_for/2` sets `avatar_url: AvatarStore.url(friend.pubkey, profile && profile.avatar_type, profile && profile.created_at)` when `friend.show_avatar` (Task 4 adds the column; until then, always); the own Person sets it unconditionally. Person moduledoc: "`avatar_url` is the stored avatar's versioned URL, nil when the key published none, the reader hides it, or the file is missing."

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/ test/media_centaur/relay_sync_test.exs`. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/media_centaur/social/avatar_store.ex lib/media_centaur/social.ex lib/media_centaur/social/person.ex test/media_centaur/social/
git commit -m "feat: Social.AvatarStore keeps a key's avatar under the data dir; save_profile keeps, removes or sets it; ingest writes the file"
```

---

### Task 4: The reader's switch: `Friend.show_avatar`

**Files:**
- Create: `priv/repo/migrations/20260928121000_friends_show_avatar.exs`
- Modify: `lib/media_centaur/social/friend.ex`, `lib/media_centaur/social.ex` (`set_show_avatar/2`, `person_for/2`), `lib/media_centaur/social/person.ex` (`show_avatar` field), `test/support/discovery_rows.ex`
- Test: `test/media_centaur/social/friend_test.exs`, `test/media_centaur/social/person_test.exs`

- [ ] **Step 1: Tests**

`friend_test.exs`:

```elixir
  describe "set_show_avatar/2" do
    test "flips the switch and broadcasts FriendChanged once per change; an unknown key is refused" do
      {:ok, %Friend{show_avatar: true}} = Social.add_friend(@pubkey, "One")
      Social.subscribe()

      assert {:ok, %Friend{show_avatar: false}} = Social.set_show_avatar(@pubkey, false)
      assert_receive {:friend_changed, %FriendChanged{pubkey: @pubkey}}, 500
      assert {:ok, %Friend{show_avatar: false}} = Social.set_show_avatar(@pubkey, false)
      refute_receive {:friend_changed, _event}, 100
      assert {:error, :not_a_friend} = Social.set_show_avatar(String.duplicate("a", 64), true)
    end
  end
```

`person_test.exs`: in the people test, after ingesting a friend's profile with an avatar (as `profile_test.exs` does, with a per-test data dir), assert `people()[@friend].avatar_url` is a string, then `Social.set_show_avatar(@friend, false)` and assert it is nil while `people()[@friend].show_avatar == false`; the own Person's `show_avatar` is true. Run: red.

- [ ] **Step 2: Migration, schema, API**

```elixir
defmodule MediaCentaur.Repo.Migrations.FriendsShowAvatar do
  @moduledoc "The reader's per-friend switch for the friend's avatar, on by default (UIDR-047)."
  use Ecto.Migration

  def change do
    alter table(:friends) do
      add :show_avatar, :boolean, null: false, default: true
    end
  end
end
```

`friend.ex`: `field :show_avatar, :boolean, default: true`; cast it; `validate_required([:pubkey, :show_avatar])`; moduledoc: "`show_avatar` is the reader's switch for the friend's avatar, on by default".

`social.ex`:

```elixir
  @doc "Shows or hides a friend's avatar for this reader. Broadcasts `FriendChanged` when it flipped."
  @spec set_show_avatar(String.t(), boolean()) :: {:ok, Friend.t()} | {:error, :not_a_friend}
  def set_show_avatar(pubkey, show?) when is_binary(pubkey) and is_boolean(show?) do
    with {:ok, friend} <- known_friend(pubkey), do: apply_change(friend, %{show_avatar: show?})
  end
```

`person.ex`: field `show_avatar: true` (default) with type `boolean()`, doc "the reader's switch; always true for the reader's own". `person_for/2` sets `show_avatar: friend.show_avatar` and `avatar_url` only when it is true. `DiscoveryRows.person/2` gains a `show_avatar:` option (default true). Migrate the dev database.

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/`. Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add priv/repo/migrations/20260928121000_friends_show_avatar.exs lib/media_centaur/social/friend.ex lib/media_centaur/social.ex lib/media_centaur/social/person.ex test/support/discovery_rows.ex test/media_centaur/social/
git commit -m "feat: the reader's per-friend avatar switch; a hidden avatar is nil on the Person"
```

---

### Task 5: Settings: choose, remove, save

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live.ex` (mount: `allow_upload`; handlers `validate_profile`, `remove_avatar`, `cancel_avatar`, `save_profile`), `lib/media_centaur_web/live/settings_live/social_section.ex` (the profile card)
- Test: `test/media_centaur_web/live/settings_live_social_test.exs`

- [ ] **Step 1: Tests**

Add to the `profile` describe (LiveView upload testing: `file_input/4` and `render_upload/2` from `Phoenix.LiveViewTest`; generate a PNG with `Image.new/3` written to a tmp path; set a per-test data dir):

```elixir
    test "choosing a picture and saving publishes a 256×256 WebP avatar; Remove clears it", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live_async!(conn, @section)
      png = Path.join(System.tmp_dir!(), "avatar-#{System.unique_integer([:positive])}.png")
      {:ok, img} = Image.new(400, 300, color: :blue)
      {:ok, _} = Image.write(img, png)

      upload = file_input(view, "#profile-form", :avatar, [%{name: "me.png", content: File.read!(png), type: "image/png"}])
      assert render_upload(upload, "me.png") =~ "me.png"
      view |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()

      me = Identity.pubkey()
      assert %{avatar_type: "image/webp"} = Social.own_profile()
      {:ok, bytes} = MediaCentaur.Social.AvatarStore.read(me, "image/webp")
      {:ok, back} = Image.from_binary(bytes)
      assert {256, 256, _} = Image.shape(back)
      assert has_element?(view, "#profile-form [data-component='identity-tile'][data-mark='avatar']")

      view |> element("#remove-avatar") |> render_click()
      view |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()
      assert %{avatar_type: nil} = Social.own_profile()
      assert has_element?(view, "#profile-form [data-component='identity-tile'][data-mark='letter']")
    end

    test "a file that is not an image is refused before anything is saved", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live_async!(conn, @section)
      upload = file_input(view, "#profile-form", :avatar, [%{name: "notes.txt", content: "hello", type: "text/plain"}])
      assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, "notes.txt")
    end
```

Run: red.

- [ ] **Step 2: The LiveView**

In `mount/3`, after the assigns:

```elixir
    socket =
      allow_upload(socket, :avatar,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 10_000_000
      )
```

and assign `avatar_removed?: false`. Handlers:

```elixir
  # The upload's validate event: LiveView needs it to track the entry.
  def handle_event("validate_profile", _params, socket), do: {:noreply, socket}

  def handle_event("remove_avatar", _params, socket),
    do: {:noreply, assign(socket, avatar_removed?: true)}

  def handle_event("cancel_avatar", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :avatar, ref)}

  def handle_event("save_profile", %{"name" => name}, socket) do
    with {:ok, avatar} <- avatar_change(socket),
         {:ok, profile} <- Social.save_profile(name, avatar) do
      {:noreply,
       socket
       |> assign(identity_npub: Identity.npub(), profile_name: profile.name, avatar_removed?: false)
       |> assign(own_person: Social.own_person())
       |> put_flash(:info, "Profile saved")}
    else
      {:error, :name_required} -> {:noreply, put_flash(socket, :error, "Your profile needs a name")}
      {:error, :name_too_long} -> {:noreply, put_flash(socket, :error, "Names are at most #{socket.assigns.name_cap} characters")}
      {:error, :bad_image} -> {:noreply, put_flash(socket, :error, "That file is not a picture we can read")}
    end
  end

  # The chosen file becomes the master; Remove means none; neither means keep.
  defp avatar_change(socket) do
    masters =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry ->
        case ImageFiles.square_webp(path, 256) do
          {:ok, bytes} -> {:ok, {:new, bytes}}
          {:error, _reason} -> {:ok, :bad_image}
        end
      end)

    case {masters, socket.assigns.avatar_removed?} do
      {[:bad_image], _} -> {:error, :bad_image}
      {[{:new, bytes}], _} -> {:ok, {:new, bytes}}
      {[], true} -> {:ok, :none}
      {[], false} -> {:ok, :keep}
    end
  end
```

Assign `own_person: Social.own_person()` in `load_social/2` and refresh it in the `:profile_updated` and `:identity_changed` clauses. Pass `uploads={@uploads}`, `own_person={@own_person}`, `avatar_removed?={@avatar_removed?}` through `section_content` to `SocialSection.render`. `ImageFiles` alias.

- [ ] **Step 3: The card**

`social_section.ex`: attrs `uploads` (`:map`, required, "the LiveView's `@uploads`; `.avatar` is the one upload"), `own_person` (`Person`, required), `avatar_removed?` (`:boolean`, required). The form:

```heex
        <form id="profile-form" phx-submit="save_profile" phx-change="validate_profile" class="space-y-3">
          <div class="flex items-center gap-3">
            <IdentityTile.identity_tile person={if @avatar_removed?, do: %Person{@own_person | avatar_url: nil}, else: @own_person} size={48} />
            <.live_file_input upload={@uploads.avatar} class="file-input file-input-bordered file-input-sm" />
            <.button
              :if={@own_person.avatar_url && !@avatar_removed?}
              id="remove-avatar"
              type="button"
              variant="dismiss"
              size="xs"
              phx-click="remove_avatar"
            >
              Remove
            </.button>
          </div>
          <p :for={entry <- @uploads.avatar.entries} class="text-xs text-base-content/60">
            {entry.client_name}
            <span :for={err <- upload_errors(@uploads.avatar, entry)} class="text-error">{upload_error_words(err)}</span>
            <button type="button" phx-click="cancel_avatar" phx-value-ref={entry.ref} class="ml-2 underline">Cancel</button>
          </p>
          <div class="flex items-center gap-2">
            <.settings_input name="name" value={@profile_name} placeholder="Name" maxlength={@name_cap} autocomplete="off" class="min-w-0 flex-1" />
            <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">
              {if @npub, do: "Save", else: "Create profile"}
            </.button>
          </div>
        </form>
```

with `defp upload_error_words(:too_large), do: "Larger than 10 MB"`, `(:not_accepted) -> "Not a JPEG, PNG or WebP"`, `(:too_many_files) -> "One picture"`. Alias `IdentityTile` and `Person`; if the struct update in HEEx raises the type warning phase 2 met, move it into a private `shown_person/2`. Run the copy through writing-copy. The card description gains "and the picture beside it, if you like".

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_social_test.exs test/media_centaur_web/storybook_compile_test.exs`. Expected: PASS. Then the browser: `~/scripts/agents/page-shot --url http://localhost:2160/settings?section=social --viewport 1920x1080 --wait-ms 3000` and Read it: the tile, the file input and the name in one card.

- [ ] **Step 4: Commit**

```bash
git add lib/media_centaur_web/live/settings_live.ex lib/media_centaur_web/live/settings_live/social_section.ex test/media_centaur_web/live/settings_live_social_test.exs
git commit -m "feat: choose a picture in Settings; the app writes the master, publishes it, and Remove clears it"
```

---

### Task 6: The switch on the card, and the Discovery handler

**Files:**
- Modify: `lib/media_centaur_web/components/discovery/person_card.ex` (the foot), `lib/media_centaur_web/live/discovery_live.ex` (`set_show_avatar` handler), `storybook/discovery/person_card.story.exs`
- Test: `test/media_centaur_web/components/discovery/person_card_test.exs`, `test/media_centaur_web/live/discovery_live_test.exs`

- [ ] **Step 1: Tests**

`person_card_test.exs`:

```elixir
  test "the opened foot carries the avatar switch, checked when the reader shows it" do
    shown = render(person: person("Nick", avatar_url: "/media-images/images/social/x.webp?v=1"), acts: [], width: :page, opened?: true)
    switch = LazyHTML.query(shown, "footer [data-role='avatar-switch']")
    assert LazyHTML.attribute(switch, "aria-checked") == ["true"]
    assert LazyHTML.attribute(switch, "phx-click") == ["set_show_avatar"]
    assert LazyHTML.attribute(switch, "phx-value-show") == ["false"]

    hidden = render(person: person("Nick", show_avatar: false), acts: [], width: :page, opened?: true)
    assert hidden |> LazyHTML.query("footer [data-role='avatar-switch']") |> LazyHTML.attribute("aria-checked") == ["false"]
    assert hidden |> LazyHTML.query("footer [data-role='avatar-switch']") |> LazyHTML.attribute("phx-value-show") == ["true"]
  end
```

`discovery_live_test.exs`, in the friends describe: add a friend, ingest a profile with an avatar (per-test data dir), open the card, assert the tile has `data-mark='avatar'`, click the switch, assert `data-mark='letter'` and `Social.friend_by_pubkey(@friend_pubkey).show_avatar == false`, click again, assert the avatar is back. Run: red.

- [ ] **Step 2: The switch**

In the foot, between the rename form and the key row:

```heex
        <div
          id={"#{@id}-avatar-switch"}
          role="switch"
          aria-checked={to_string(@person.show_avatar)}
          class="-mx-2 flex cursor-pointer items-center gap-3 rounded-lg px-2 py-1.5 hover:bg-base-content/[0.04]"
          data-role="avatar-switch"
          data-nav-item
          tabindex="0"
          phx-click="set_show_avatar"
          phx-value-pubkey={@person.pubkey}
          phx-value-show={to_string(not @person.show_avatar)}
        >
          <input type="checkbox" class="toggle toggle-sm toggle-info pointer-events-none" checked={@person.show_avatar} tabindex="-1" />
          <span class="text-sm">Show their picture</span>
        </div>
```

(The switch has its own `phx-click`, so the card's press is not reached; the modal-panel swallow is not needed here.) Moduledoc: the foot's switch. Handler in `discovery_live.ex`:

```elixir
  def handle_event("set_show_avatar", %{"pubkey" => pubkey, "show" => show}, socket) do
    case Social.set_show_avatar(pubkey, show == "true") do
      {:ok, _friend} -> {:noreply, socket |> load_people() |> load_activities()}
      {:error, :not_a_friend} -> {:noreply, put_flash(socket, :error, "That friend is no longer on your list")}
    end
  end
```

Story: `page_opened` shows the switch on; add `page_opened_avatar_hidden` with `%{friend() | show_avatar: false}`; add an avatar to `friend/0`'s fixture in one variation (`rail_friend_avatar`) so the tile's avatar mark shows on a card. Run the copy ("Show their picture") through writing-copy.

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/ test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/storybook_render_test.exs`. Expected: PASS. Browser: open a friend's card on `http://localhost:2160/discovery/friends` with `chromium-probe`, click the switch, confirm the tile's `data-mark` flips.

- [ ] **Step 3: Commit**

```bash
git add lib/media_centaur_web/components/discovery/person_card.ex lib/media_centaur_web/live/discovery_live.ex storybook/discovery/person_card.story.exs test/media_centaur_web/components/discovery/person_card_test.exs test/media_centaur_web/live/discovery_live_test.exs
git commit -m "feat: the card's foot switches a friend's picture on or off for this reader"
```

---

### Task 7: The whole suite and `precommit`

Run `~/scripts/agents/agent-mix test` then `~/scripts/agents/agent-mix precommit` (foreground, timeout 600000). Fix what they report in the owning module; commit as `chore: precommit clean after the avatar`.

---

### Task 8: Docs, protocol page, wiki, campaign, spec

- `docs/social-protocol.md` § Profile: the `avatar` object (type, data), the three types, the 64 KB decoded cap inclusive, the signature rule, "a reader never decodes an avatar; it stores the bytes and serves them with the declared type"; the sender's master (256×256 WebP); a Changes row.
- `docs/social.md`: § Event shape (the avatar), § Storage/Web layer (`AvatarStore`, the URL, the switch, the upload), the data-dir layout line; `docs/architecture.md`: Social's row gains `{data_dir}/images/social/`; `docs/GLOSSARY.md`: Avatar, Show avatar; the spec: § Storage drops `avatar_path` and names `AvatarStore`; the identity tile moduledoc drops "No avatar exists yet"; `Person`'s `avatar_url` sentence loses "nothing sets it yet".
- Wiki: `Settings-Reference.md` (the picture: choose, save, remove; the size it is stored at), `Social.md` (friends see your picture; **Show their picture** on a friend's card), `Troubleshooting.md` if the file-not-a-picture flash deserves a row.
- `campaigns/profiles.md`: status "Phase 3 shipped on main <date>"; decisions (the unify pass: one path derivation, no path column, no `?w=`); next steps: phase 4 (records to accepted, closure by destination, the release after phase 2's ship drops `nickname`).
- Commit the app docs and the wiki; push neither.
