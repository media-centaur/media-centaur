# Viewer Profiles Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `Profiles` context, the "Who's watching?" picker, the session-held active profile, the shell switcher and Settings → Profiles, with every watching row still shared, so two profiles behave as one until phase 2.

**Architecture:** A new bounded context `MediaCentaur.Profiles` (no deps) owns `profiles` rows and their pictures. The active profile is the `"profile_id"` key of the signed session cookie, set by one `POST /profiles/:id/activate` route and read by one `on_mount` hook (`Live.ProfileAware`) in `live_session :default`. The identity tile widens to draw any person from three facts. Five convergences (unify pass, 2026-10-06) collapse duplicated picture, name and error logic so the social profile and the viewer profile share one implementation each.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto + SQLite (`ecto_sqlite3`), Phoenix Storybook, bun tests for the input system, `mix precommit` via `~/scripts/agents/agent-mix`.

**Spec:** `docs/superpowers/specs/2026-10-06-viewer-profiles-design.md`. **Records:** ADR-078, UIDR-053. **Campaign:** `campaigns/viewer-profiles.md`.

**Working rules for this plan**

- Another agent shares this checkout. Do all work on branch `viewer-profiles` in a sibling worktree: `git worktree add ../media-centaur-app-viewer-profiles -b viewer-profiles` and `cd` there. The owner merges.
- Never run `mix` directly; run `~/scripts/agents/agent-mix` (CLAUDE.md). `agent-mix test <file>` for one file, `agent-mix precommit` at the end of every task that changes Elixir.
- Test first: write the failing test, run it, see it fail for the stated reason, implement, run it, commit.
- Every test module states `async:`; DB tests use `MediaCentaur.DataCase`/`MediaCentaurWeb.ConnCase` with `async: false`; pure tests use `MediaCentaur.Case, async: true`.
- Generic names in fixtures (`Sample Name`, `Ana`); no real people.
- Commit per task with a conventional message.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/media_centaur/hue.ex` (moved from `social/hue.ex`) | The hue value: palette, `random/0`, `valid?/1`, `parse/1`. Two contexts carry a hue. |
| `lib/media_centaur/display_name.ex` | The one rule for a person's name: trimmed, present, at most 50 characters. Used by Social and Profiles. |
| `lib/media_centaur/image_files.ex` | Gains `write_file/2`, `remove_file/1`, `url_if_present/2`: the three primitives every data-dir picture store needs. |
| `lib/media_centaur/profiles.ex` | The context facade: list/get/count, add/rename/set_hue/set_picture/remove, `picture_url/1`, `subscribe/0`. |
| `lib/media_centaur/profiles/profile.ex` | The `profiles` schema and changeset. |
| `lib/media_centaur/profiles/picture_store.ex` | One 256×256 WebP per profile under `{data_dir}/images/profiles/<id>.webp`. |
| `lib/media_centaur/profiles/events.ex` | `ProfileAdded`, `ProfileChanged`, `ProfileRemoved` on `profiles:updates`. |
| `lib/media_centaur/topics.ex` | Gains `profiles_updates/0` and its table row. |
| `priv/repo/migrations/20261006120000_viewer_profiles.exs` | Renames `profiles` → `social_profiles`, creates the new `profiles`, inserts the owner profile "Me". |
| `lib/media_centaur/social/profile.ex` | Schema table becomes `social_profiles`. |
| `lib/media_centaur/social/avatar_store.ex` | Uses the `ImageFiles` primitives. |
| `lib/media_centaur_web/components/picture_field.ex` | Gains `consume_change/5` and the pure `change/2`: one upload-to-master path for the social avatar, the profile picture and the app banner. |
| `lib/media_centaur_web/components/social/identity_tile.ex` | Draws from `name`, `picture_url`, `hue`, `own?`; gains `person_attrs/1` and `crop_previews/1`; size 96. |
| `lib/media_centaur_web/profile_words.ex` | The words for every error a person-record form can show. |
| `lib/media_centaur_web/live/profile_aware.ex`, `profile_aware/logic.ex` | The `on_mount` hook and its pure resolution rule. |
| `lib/media_centaur_web/controllers/profile_controller.ex`, `profile_controller/return_to.ex` | The activate route and the local-path guard. |
| `lib/media_centaur_web/live/profiles_live.ex` | The picker at `/profiles`. |
| `lib/media_centaur_web/live/settings_live/profiles_section.ex`, `profiles_logic.ex` | Settings → Profiles cards and the section's pure helpers. |
| `lib/media_centaur_web/components/layouts.ex` | The sidebar switcher; `profile` and `profiles` attrs. |
| `assets/js/input/profiles_behavior.js`, `config.js`, `page_behavior.js` | The picker's nav zone. |

---

### Task 0: Branch in a sibling worktree

- [ ] **Step 1: Create the worktree and branch**

```bash
cd /home/shawn/src/media-centaur/media-centaur-app
git worktree add ../media-centaur-app-viewer-profiles -b viewer-profiles
cd ../media-centaur-app-viewer-profiles
```

- [ ] **Step 2: Confirm the suite is green before any change**

Run: `~/scripts/agents/agent-mix test`
Expected: all tests pass, 0 failures.

---

### Task 1: `MediaCentaur.Hue` (the hue leaves the Social context)

**Files:**
- Move: `lib/media_centaur/social/hue.ex` → `lib/media_centaur/hue.ex`
- Move: `test/media_centaur/social/hue_test.exs` → `test/media_centaur/hue_test.exs`
- Modify: every file aliasing `MediaCentaur.Social.Hue` (15 files, listed in step 3)
- Modify: `lib/media_centaur/social.ex` (drop `Hue` from `exports`)

- [ ] **Step 1: Move the test and rename its module**

```bash
git mv test/media_centaur/social/hue_test.exs test/media_centaur/hue_test.exs
sed -i 's/MediaCentaur.Social.HueTest/MediaCentaur.HueTest/; s/MediaCentaur.Social.Hue\b/MediaCentaur.Hue/' test/media_centaur/hue_test.exs
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/hue_test.exs`
Expected: FAIL — `MediaCentaur.Hue` is not available (UndefinedFunctionError).

- [ ] **Step 3: Move the module and repoint every alias**

```bash
git mv lib/media_centaur/social/hue.ex lib/media_centaur/hue.ex
sed -i 's/defmodule MediaCentaur.Social.Hue do/defmodule MediaCentaur.Hue do/' lib/media_centaur/hue.ex
for f in lib/media_centaur_web/components/social/identity_tile.ex \
         lib/media_centaur_web/components/social/person_card.ex \
         lib/media_centaur_web/components/social/hue_swatches.ex \
         lib/media_centaur_web/live/settings_live/social_section.ex \
         lib/media_centaur_web/live/settings_live.ex \
         lib/media_centaur_web/live/social_live.ex \
         lib/media_centaur/social.ex \
         lib/media_centaur/social/person.ex \
         lib/media_centaur/social/profile/translation.ex \
         test/media_centaur_web/live/settings_live_social_test.exs \
         test/media_centaur_web/components/social/hue_swatches_test.exs \
         storybook/social/identity_tile.story.exs \
         storybook/social/hue_swatches.story.exs; do
  sed -i 's/MediaCentaur\.Social\.Hue\b/MediaCentaur.Hue/g' "$f"
done
```

Then open `lib/media_centaur/hue.ex` and make the head read:

```elixir
defmodule MediaCentaur.Hue do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  A person's colour is a hue (UIDR-048): an integer angle 0–359 on one
  oklch ring whose lightness and chroma the theme fixes (`--person-l`,
  `--person-c` in `app.css`), so nothing published can be dark, pastel
  or grey and a letter's contrast never depends on the choice. Two
  contexts carry one: the social profile's optional `hue` field on the
  wire (ADR-073; `social_profiles.hue` and the reader's
  `friends.hue_override`) and a viewer profile's `profiles.hue`
  (ADR-078). User copy says *colour*; code and the wire say hue.

  The palette is the eight named angles the swatch row offers; any
  other angle comes from the slider. `random/0` seeds a new social
  profile's form. A person with no hue is drawn at 250, the primary's
  angle, by CSS alone (`var(--hue, 250)`); no function here supplies a
  default.
  """
```

In `lib/media_centaur/social.ex` remove the `Hue,` line from the `exports:` list and change `alias MediaCentaur.Social.Hue` to `alias MediaCentaur.Hue`.

- [ ] **Step 4: Compile and run the affected tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/hue_test.exs test/media_centaur_web/live/settings_live_social_test.exs test/media_centaur_web/components/social/`
Expected: PASS. Then `grep -rn "Social.Hue" lib test storybook docs` must print nothing but prose in `docs/`; fix any code hit.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: the hue is MediaCentaur.Hue, carried by two contexts"
```

---

### Task 2: `MediaCentaur.DisplayName` (one name rule)

**Files:**
- Create: `lib/media_centaur/display_name.ex`
- Test: `test/media_centaur/display_name_test.exs`
- Modify: `lib/media_centaur/social.ex` (`check_name/1` delegates), `lib/media_centaur/social/profile/translation.ex` (`max_name_length/0` delegates)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.DisplayNameTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.DisplayName

  test "a name is trimmed, present and at most the cap" do
    assert DisplayName.check("  Sample Name ") == {:ok, "Sample Name"}
    assert DisplayName.check("   ") == {:error, :name_required}
    assert DisplayName.check("") == {:error, :name_required}
    assert DisplayName.check(String.duplicate("x", 50)) == {:ok, String.duplicate("x", 50)}
    assert DisplayName.check(String.duplicate("x", 51)) == {:error, :name_too_long}
  end

  test "the cap is the social wire's cap" do
    assert DisplayName.max_length() == 50
    assert MediaCentaur.Social.Profile.Translation.max_name_length() == DisplayName.max_length()
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/display_name_test.exs`
Expected: FAIL — `MediaCentaur.DisplayName` undefined.

- [ ] **Step 3: Write the module and delegate the two existing sites**

`lib/media_centaur/display_name.ex`:

```elixir
defmodule MediaCentaur.DisplayName do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  The one rule for a person's name wherever the app holds one: the
  social profile's published name (`Social.save_profile/3`, the wire cap
  in `Social.Profile.Translation`) and a viewer profile's name
  (`Profiles`). Trimmed, present, and at most `max_length/0` characters.
  """

  @max_length 50

  @doc "The cap, in characters."
  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @doc "The trimmed name, or why it was refused."
  @spec check(String.t()) :: {:ok, String.t()} | {:error, :name_required | :name_too_long}
  def check(name) when is_binary(name) do
    trimmed = String.trim(name)

    cond do
      trimmed == "" -> {:error, :name_required}
      String.length(trimmed) > @max_length -> {:error, :name_too_long}
      true -> {:ok, trimmed}
    end
  end
end
```

In `lib/media_centaur/social.ex` replace the body of `check_name/1` with a delegate and delete the private helpers it used:

```elixir
  @doc """
  The profile name rule, the one `save_profile/3` applies: `DisplayName.check/1`.
  The form checks it before it consumes a chosen picture, so a name error
  costs nothing.
  """
  @spec check_name(String.t()) :: {:ok, String.t()} | {:error, :name_required | :name_too_long}
  defdelegate check_name(name), to: MediaCentaur.DisplayName, as: :check
```

Delete `present_name/1` and `within_name_cap/1` (grep `defp present_name\|defp within_name_cap` in `social.ex`). In `lib/media_centaur/social/profile/translation.ex` change the `max_name_length/0` body to `MediaCentaur.DisplayName.max_length()` (keep its `@doc`, it is the wire's statement of the cap).

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/display_name_test.exs test/media_centaur/social/ test/media_centaur_web/live/settings_live_social_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: one DisplayName rule for the social profile and the viewer profile"
```

---

### Task 3: `ImageFiles` primitives (one picture-store idiom)

**Files:**
- Modify: `lib/media_centaur/image_files.ex`
- Modify: `lib/media_centaur/social/avatar_store.ex`, `lib/media_centaur/apps/artwork.ex`
- Test: `test/media_centaur/image_files_test.exs` (append; create if absent)

- [ ] **Step 1: Write the failing tests**

Append to `test/media_centaur/image_files_test.exs` (create the module with `use MediaCentaur.Case, async: false` and `import MediaCentaur.TmpDataDir` if the file does not exist):

```elixir
  describe "data-dir file primitives" do
    setup :setup_tmp_data_dir

    test "write_file creates the directory, remove_file tolerates absence, url_if_present answers only for a file on disk",
         %{data_dir: data_dir} do
      relative = "images/sample/one.webp"
      assert ImageFiles.url_if_present(relative, 7) == nil

      assert :ok = ImageFiles.write_file(relative, "bytes")
      assert File.read!(Path.join(data_dir, relative)) == "bytes"
      assert ImageFiles.url_if_present(relative, 7) == "/media-images/images/sample/one.webp?v=7"

      assert :ok = ImageFiles.remove_file(relative)
      assert :ok = ImageFiles.remove_file(relative)
      assert ImageFiles.url_if_present(relative, 7) == nil
    end
  end
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/image_files_test.exs`
Expected: FAIL — `ImageFiles.url_if_present/2` undefined.

- [ ] **Step 3: Add the primitives and use them in the two stores**

Add to `lib/media_centaur/image_files.ex` after `on_disk_path/1`:

```elixir
  @doc """
  Writes bytes at a data-dir-relative path, creating its directory. The
  one write every data-dir picture store (`Social.AvatarStore`,
  `Profiles.PictureStore`, `Apps.Artwork`) makes.
  """
  @spec write_file(String.t(), binary()) :: :ok
  def write_file(relative_path, bytes) when is_binary(relative_path) and is_binary(bytes) do
    dest = on_disk_path(relative_path)
    File.mkdir_p!(Path.dirname(dest))
    File.write!(dest, bytes)
  end

  @doc "Removes the file at a data-dir-relative path. A file already gone is what we wanted."
  @spec remove_file(String.t()) :: :ok
  def remove_file(relative_path) when is_binary(relative_path) do
    path = on_disk_path(relative_path)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> raise File.Error, reason: reason, action: "remove file", path: path
    end
  end

  @doc "The versioned URL for a data-dir-relative path, or nil when no file is there."
  @spec url_if_present(String.t(), non_neg_integer()) :: String.t() | nil
  def url_if_present(relative_path, version) when is_binary(relative_path) do
    if File.regular?(on_disk_path(relative_path)), do: web_path(relative_path, version)
  end
```

In `lib/media_centaur/social/avatar_store.ex` make `write/3` and `url/3` read:

```elixir
  def write(pubkey, type, bytes) when is_binary(pubkey) and is_binary(type) and is_binary(bytes) do
    :ok = delete(pubkey)
    ImageFiles.write_file(relative_path(pubkey, type), bytes)
  end
```

```elixir
  def url(pubkey, type, version), do: ImageFiles.url_if_present(relative_path(pubkey, type), version)
```

(`delete/1` stays: it removes every extension for the key, which is this store's own rule.)

In `lib/media_centaur/apps/artwork.ex`, in `store_bytes/3`, replace the `File.mkdir_p!` + `File.write!` pair with `ImageFiles.write_file(relative_path(role, app_id), bytes)` and keep the function's return shape.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/image_files_test.exs test/media_centaur/social/ test/media_centaur/apps/ test/media_centaur_web/live/settings_live_social_test.exs test/media_centaur_web/live/apps_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: ImageFiles owns the write, remove and url primitives of every picture store"
```

---

### Task 4: The migration, `social_profiles`, and the Profiles context

**Files:**
- Create: `priv/repo/migrations/20261006120000_viewer_profiles.exs`
- Modify: `lib/media_centaur/social/profile.ex` (`schema "social_profiles"`)
- Create: `lib/media_centaur/profiles.ex`, `lib/media_centaur/profiles/profile.ex`, `lib/media_centaur/profiles/events.ex`, `lib/media_centaur/profiles/picture_store.ex`
- Modify: `lib/media_centaur/topics.ex`
- Modify: `test/support/factory.ex` (`create_profile/1`)
- Test: `test/media_centaur/profiles_test.exs`

- [ ] **Step 1: Write the failing context test**

`test/media_centaur/profiles_test.exs`:

```elixir
defmodule MediaCentaur.ProfilesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmpDataDir

  alias MediaCentaur.Profiles
  alias MediaCentaur.Profiles.Events
  alias MediaCentaur.Profiles.PictureStore
  alias MediaCentaur.Profiles.Profile

  setup :setup_tmp_data_dir

  test "the upgrade left one owner profile named Me" do
    assert [%Profile{name: "Me", hue: nil, picture_at: nil}] = Profiles.list()
    assert Profiles.count() == 1
  end

  test "add trims and checks the name, orders by creation, caps at eight, and broadcasts" do
    Profiles.subscribe()
    assert {:ok, %Profile{name: "Ana"} = ana} = Profiles.add("  Ana ")
    assert_receive {:profile_added, %Events.ProfileAdded{profile: %Profile{id: id}}}
    assert id == ana.id
    assert ["Me", "Ana"] = Enum.map(Profiles.list(), & &1.name)

    assert {:error, :name_required} = Profiles.add("   ")
    assert {:error, :name_too_long} = Profiles.add(String.duplicate("x", 51))

    for n <- 3..8, do: assert({:ok, _} = Profiles.add("Person #{n}"))
    assert {:error, :too_many_profiles} = Profiles.add("One too many")
    assert Profiles.count() == 8
  end

  test "get takes an id, and answers nil for an unknown or malformed one" do
    [me] = Profiles.list()
    assert %Profile{name: "Me"} = Profiles.get(me.id)
    assert Profiles.get(Ecto.UUID.generate()) == nil
    assert Profiles.get("not-a-uuid") == nil
  end

  test "rename and set_hue save on the act and broadcast; a bad hue is refused" do
    [me] = Profiles.list()
    Profiles.subscribe()

    assert {:ok, %Profile{name: "Sample Name"}} = Profiles.rename(me, " Sample Name ")
    assert_receive {:profile_changed, %Events.ProfileChanged{profile: %Profile{name: "Sample Name"}}}
    assert {:error, :name_required} = Profiles.rename(me, "")

    assert {:ok, %Profile{hue: 195}} = Profiles.set_hue(me, 195)
    assert_receive {:profile_changed, %Events.ProfileChanged{profile: %Profile{hue: 195}}}
    assert {:ok, %Profile{hue: nil}} = Profiles.set_hue(me, nil)
    assert {:error, :invalid_hue} = Profiles.set_hue(me, 360)
  end

  test "a picture is one file per profile; the URL carries the row's version; none removes it",
       %{data_dir: data_dir} do
    [me] = Profiles.list()
    assert Profiles.picture_url(me) == nil

    assert {:ok, %Profile{picture_at: %DateTime{} = at} = with_picture} = Profiles.set_picture(me, {:new, "webp-bytes"})
    assert File.read!(Path.join(data_dir, "images/profiles/#{me.id}.webp")) == "webp-bytes"
    assert Profiles.picture_url(with_picture) == "/media-images/images/profiles/#{me.id}.webp?v=#{DateTime.to_unix(at)}"

    assert {:ok, %Profile{picture_at: nil} = without} = Profiles.set_picture(with_picture, :none)
    refute File.exists?(Path.join(data_dir, "images/profiles/#{me.id}.webp"))
    assert Profiles.picture_url(without) == nil
  end

  test "remove refuses the last profile, otherwise deletes the row and the picture and broadcasts",
       %{data_dir: data_dir} do
    [me] = Profiles.list()
    assert {:error, :last_profile} = Profiles.remove(me)

    {:ok, ana} = Profiles.add("Ana")
    {:ok, ana} = Profiles.set_picture(ana, {:new, "webp-bytes"})
    Profiles.subscribe()

    assert :ok = Profiles.remove(ana)
    assert_receive {:profile_removed, %Events.ProfileRemoved{id: id}}
    assert id == ana.id
    assert Profiles.get(ana.id) == nil
    refute File.exists?(Path.join(data_dir, "images/profiles/#{ana.id}.webp"))
    assert PictureStore.url(ana.id, 1) == nil
  end

  test "the social profile schema reads social_profiles and the table carries its unique key" do
    assert MediaCentaur.Social.Profile.__schema__(:source) == "social_profiles"

    %{columns: columns, rows: rows} = Repo.query!("PRAGMA index_list('social_profiles')")
    indexes = Enum.map(rows, &Map.new(Enum.zip(columns, &1)))

    assert [%{"name" => "social_profiles_pubkey_index"}] =
             Enum.filter(indexes, &(&1["unique"] == 1 and &1["origin"] != "pk"))

    %{columns: columns, rows: rows} = Repo.query!("PRAGMA index_info('social_profiles_pubkey_index')")
    assert ["pubkey"] = Enum.map(rows, &Map.new(Enum.zip(columns, &1))["name"])
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/profiles_test.exs`
Expected: FAIL — `MediaCentaur.Profiles` undefined.

- [ ] **Step 3: The migration**

`priv/repo/migrations/20261006120000_viewer_profiles.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.ViewerProfiles do
  @moduledoc """
  Viewer profiles (ADR-078). The social context's `profiles` — what a
  key published about itself — becomes `social_profiles`, so the plain
  word is the viewer profile's. The new `profiles` holds one row per
  person who watches here, and the upgrade inserts the owner profile,
  "Me", so a single-profile install never sees the picker. Phase 2
  assigns every watching row to the oldest profile.
  """
  use Ecto.Migration

  def up do
    drop unique_index(:profiles, [:pubkey])
    rename table(:profiles), to: table(:social_profiles)
    create unique_index(:social_profiles, [:pubkey])

    create table(:profiles, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :hue, :integer
      add :picture_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    execute(fn ->
      # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
      repo().query!(
        """
        INSERT INTO profiles (id, name, inserted_at, updated_at)
        SELECT ?1, 'Me', datetime('now'), datetime('now')
        WHERE NOT EXISTS (SELECT 1 FROM profiles)
        """,
        [Ecto.UUID.generate()]
      )
    end)
  end

  def down do
    drop table(:profiles)
    drop unique_index(:social_profiles, [:pubkey])
    rename table(:social_profiles), to: table(:profiles)
    create unique_index(:profiles, [:pubkey])
  end
end
```

In `lib/media_centaur/social/profile.ex` change `schema "profiles" do` to `schema "social_profiles" do` and the moduledoc's first line to "What a public key published about itself (ADR-073) — the social profile, table `social_profiles`: …".

Verify nothing else names the old table: `grep -rn '"profiles"' lib priv/repo/data_migrations` must print only the new `Profiles.Profile` schema line (after step 4).

- [ ] **Step 4: Topics, Events, schema, store, context**

Add to `lib/media_centaur/topics.ex` beside `apps_updates/0`:

```elixir
  def profiles_updates, do: "profiles:updates"
```

and a row in the source-topics table in its moduledoc, after the `apps:updates` row:

```markdown
  | `profiles:updates` | `Profiles.Events` | `{:profile_added, _}`, `{:profile_changed, _}`, `{:profile_removed, _}` — each a typed struct (ADR-060) |
```

`lib/media_centaur/profiles/events.ex`:

```elixir
defmodule MediaCentaur.Profiles.Events do
  @moduledoc """
  Typed payloads for `profiles:updates` (ADR-060): one struct per
  message, a single `broadcast/1`. The one `Topics.publish` in the
  Profiles context.
  """

  alias MediaCentaur.Profiles.Profile
  alias MediaCentaur.Topics

  defmodule ProfileAdded do
    @moduledoc "A profile was added."
    @enforce_keys [:profile]
    defstruct [:profile]
    @type t :: %__MODULE__{profile: Profile.t()}
  end

  defmodule ProfileChanged do
    @moduledoc "A profile's name, hue or picture changed; the struct is the row after the change."
    @enforce_keys [:profile]
    defstruct [:profile]
    @type t :: %__MODULE__{profile: Profile.t()}
  end

  defmodule ProfileRemoved do
    @moduledoc "A profile was removed; a session using it drops to the picker."
    @enforce_keys [:id]
    defstruct [:id]
    @type t :: %__MODULE__{id: Ecto.UUID.t()}
  end

  @type t :: ProfileAdded.t() | ProfileChanged.t() | ProfileRemoved.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%ProfileAdded{} = event), do: publish({:profile_added, event})
  def broadcast(%ProfileChanged{} = event), do: publish({:profile_changed, event})
  def broadcast(%ProfileRemoved{} = event), do: publish({:profile_removed, event})

  defp publish(message), do: Topics.publish(Topics.profiles_updates(), message)
end
```

`lib/media_centaur/profiles/profile.ex`:

```elixir
defmodule MediaCentaur.Profiles.Profile do
  @moduledoc """
  One person who watches on this install (ADR-078): a name, an optional
  hue (`MediaCentaur.Hue`), and `picture_at` — when the picture file was
  last set, nil for none; the file itself is `PictureStore`'s and the
  time doubles as the URL's version. Phase 2 hangs the watching rows
  off `id`. Not `MediaCentaur.Social.Profile`, the published social
  profile of a key.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.DisplayName

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "profiles" do
    field :name, :string
    field :hue, :integer
    field :picture_at, :utc_datetime

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "The name is already checked by `DisplayName.check/1`; the hue by `Hue.valid?/1`. This is the row's last guard."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(profile \\ %__MODULE__{}, attrs) do
    profile
    |> cast(attrs, [:name, :hue, :picture_at])
    |> validate_required([:name])
    |> validate_length(:name, max: DisplayName.max_length())
    |> validate_number(:hue, greater_than_or_equal_to: 0, less_than_or_equal_to: 359)
  end
end
```

`lib/media_centaur/profiles/picture_store.ex`:

```elixir
defmodule MediaCentaur.Profiles.PictureStore do
  @moduledoc """
  Where a profile's picture lives: `{data_dir}/images/profiles/<id>.webp`,
  one 256×256 WebP master per profile, the data-dir picture idiom over
  `ImageFiles`' primitives (`Social.AvatarStore` is the same idiom keyed
  by pubkey). Disk is the ledger; the URL carries `picture_at` as `?v=`
  so a replaced picture mints a new URL and an unchanged one stays
  immutable in the browser.
  """

  alias MediaCentaur.ImageFiles

  @subdir "images/profiles"
  @side 256
  @max_bytes 262_144

  @doc "The master's shape, for `ImageFiles.webp_master/4`."
  @spec master_size() :: {pos_integer(), pos_integer()}
  def master_size, do: {@side, @side}

  @doc "The master's byte cap, for `ImageFiles.webp_master/4`: generous, since nothing goes on the wire."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "The data-dir-relative path of a profile's picture."
  @spec relative_path(Ecto.UUID.t()) :: String.t()
  def relative_path(id), do: Path.join(@subdir, id <> ".webp")

  @spec write(Ecto.UUID.t(), binary()) :: :ok
  def write(id, bytes), do: ImageFiles.write_file(relative_path(id), bytes)

  @spec delete(Ecto.UUID.t()) :: :ok
  def delete(id), do: ImageFiles.remove_file(relative_path(id))

  @doc "The versioned URL, or nil when the file is not on disk."
  @spec url(Ecto.UUID.t(), non_neg_integer()) :: String.t() | nil
  def url(id, version), do: ImageFiles.url_if_present(relative_path(id), version)
end
```

`lib/media_centaur/profiles.ex`:

```elixir
defmodule MediaCentaur.Profiles do
  use Boundary,
    deps: [],
    exports: [
      Events,
      Events.ProfileAdded,
      Events.ProfileChanged,
      Events.ProfileRemoved,
      PictureStore,
      Profile
    ]

  @moduledoc """
  Bounded context for the people who watch on this install (ADR-078):
  one `Profile` per person — a name, a hue, a picture — picked on the
  screen (`/profiles`, UIDR-053) and edited under Settings → Profiles.
  Phase 2 makes the watching rows theirs. Nothing here knows which
  profile a session is using; that is the web layer's (`Live.ProfileAware`).

  At most `max_profiles/0` profiles; never fewer than one through
  `remove/1`. Broadcasts typed events on `profiles:updates`
  (`subscribe/0`).
  """

  import Ecto.Query

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Hue
  alias MediaCentaur.Profiles.Events
  alias MediaCentaur.Profiles.PictureStore
  alias MediaCentaur.Profiles.Profile
  alias MediaCentaur.Repo
  alias MediaCentaur.Topics

  @max_profiles 8

  @typedoc "What `set_picture/2` does: remove the picture, or set the WebP master `ImageFiles.webp_master/4` made."
  @type picture_change :: :none | {:new, binary()}

  @doc "Subscribe the caller to profile events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.profiles_updates())

  @doc "The most profiles an install holds."
  @spec max_profiles() :: pos_integer()
  def max_profiles, do: @max_profiles

  @doc "Every profile, oldest first — the owner profile leads."
  @spec list() :: [Profile.t()]
  def list, do: Repo.all(from profile in Profile, order_by: [asc: profile.inserted_at, asc: profile.id])

  @doc "A profile by id; nil for an unknown or malformed id."
  @spec get(String.t()) :: Profile.t() | nil
  def get(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Profile, uuid)
      :error -> nil
    end
  end

  def get(_not_a_string), do: nil

  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(Profile, :count)

  @doc "Adds a profile under `DisplayName.check/1`, below the cap. Broadcasts `ProfileAdded`."
  @spec add(String.t()) ::
          {:ok, Profile.t()} | {:error, :name_required | :name_too_long | :too_many_profiles}
  def add(name) when is_binary(name) do
    with {:ok, name} <- DisplayName.check(name),
         :ok <- under_cap() do
      {:ok, profile} = %Profile{} |> Profile.changeset(%{name: name}) |> Repo.insert()
      Events.broadcast(%Events.ProfileAdded{profile: profile})
      {:ok, profile}
    end
  end

  @doc "Renames under `DisplayName.check/1`. Broadcasts `ProfileChanged`."
  @spec rename(Profile.t(), String.t()) ::
          {:ok, Profile.t()} | {:error, :name_required | :name_too_long}
  def rename(%Profile{} = profile, name) when is_binary(name) do
    with {:ok, name} <- DisplayName.check(name) do
      profile |> Profile.changeset(%{name: name}) |> update_and_broadcast()
    end
  end

  @doc "Sets the hue (UIDR-048), nil for none; out of range is refused. Broadcasts `ProfileChanged`."
  @spec set_hue(Profile.t(), Hue.t() | nil) :: {:ok, Profile.t()} | {:error, :invalid_hue}
  def set_hue(%Profile{} = profile, nil), do: profile |> Profile.changeset(%{hue: nil}) |> update_and_broadcast()

  def set_hue(%Profile{} = profile, hue) do
    if Hue.valid?(hue),
      do: profile |> Profile.changeset(%{hue: hue}) |> update_and_broadcast(),
      else: {:error, :invalid_hue}
  end

  @doc """
  Sets or removes the picture: the row first, then the file, so a write
  that fails after the row reads as no picture until the next save
  rather than serving new bytes under the old URL. Broadcasts `ProfileChanged`.
  """
  @spec set_picture(Profile.t(), picture_change()) :: {:ok, Profile.t()}
  def set_picture(%Profile{} = profile, :none) do
    {:ok, updated} = profile |> Profile.changeset(%{picture_at: nil}) |> update_and_broadcast()
    if profile.picture_at, do: :ok = PictureStore.delete(profile.id)
    {:ok, updated}
  end

  def set_picture(%Profile{} = profile, {:new, bytes}) when is_binary(bytes) do
    now = DateTime.utc_now(:second)
    {:ok, updated} = profile |> Profile.changeset(%{picture_at: now}) |> update_and_broadcast()
    :ok = PictureStore.write(profile.id, bytes)
    {:ok, updated}
  end

  @doc "The picture's versioned URL, or nil when the profile has none or the file is missing."
  @spec picture_url(Profile.t()) :: String.t() | nil
  def picture_url(%Profile{picture_at: nil}), do: nil
  def picture_url(%Profile{id: id, picture_at: at}), do: PictureStore.url(id, DateTime.to_unix(at))

  @doc """
  Removes a profile and its picture. Refuses the last one: the install
  always has someone to watch as. Phase 2 cascades the watching rows by
  foreign key. Broadcasts `ProfileRemoved`.
  """
  @spec remove(Profile.t()) :: :ok | {:error, :last_profile}
  def remove(%Profile{} = profile) do
    if count() <= 1 do
      {:error, :last_profile}
    else
      {:ok, _deleted} = Repo.delete(profile)
      if profile.picture_at, do: :ok = PictureStore.delete(profile.id)
      Events.broadcast(%Events.ProfileRemoved{id: profile.id})
      :ok
    end
  end

  defp under_cap, do: if(count() < @max_profiles, do: :ok, else: {:error, :too_many_profiles})

  defp update_and_broadcast(changeset) do
    with {:ok, profile} <- Repo.update(changeset) do
      Events.broadcast(%Events.ProfileChanged{profile: profile})
      {:ok, profile}
    end
  end
end
```

Add to `test/support/factory.ex`, beside `create_app/1`:

```elixir
  @doc "Persists a viewer profile through `MediaCentaur.Profiles.add/1`; `hue:` and `name:` override."
  def create_profile(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {:ok, profile} = MediaCentaur.Profiles.add(Map.get(attrs, :name, "Sample Profile"))

    case Map.get(attrs, :hue) do
      nil -> profile
      hue -> MediaCentaur.Profiles.set_hue(profile, hue) |> elem(1)
    end
  end
```

- [ ] **Step 5: Migrate the test database and run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/profiles_test.exs test/media_centaur/social/`
Expected: PASS (the `test` alias migrates first; if "Me" is missing, run `MIX_ENV=test ~/scripts/agents/agent-mix ecto.migrate` and re-run).

- [ ] **Step 6: Update the two docs that name the social table**

In `docs/social.md` and `docs/architecture.md`, replace the Social row's "`profiles` tables" / "`profiles` table" with `social_profiles`, and add this row to the bounded-contexts table in `docs/architecture.md` after `MediaCentaur.Apps`:

```markdown
| `MediaCentaur.Profiles` | `profiles` table, `{data_dir}/images/profiles/` (one WebP master per profile, `Profiles.PictureStore`) | The people who watch on this install (ADR-078): a name, a hue, a picture, picked on the screen (`/profiles`, UIDR-053). Phase 2 of the viewer-profiles campaign hangs the watching rows off a profile. No deps; broadcasts on `profiles:updates`. |
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: the Profiles context — one row per person who watches here"
```

---

### Task 5: `ProfileWords` (one set of words)

**Files:**
- Create: `lib/media_centaur_web/profile_words.ex`
- Test: `test/media_centaur_web/profile_words_test.exs`
- Modify: `lib/media_centaur_web/live/settings_live.ex` (the social save's `else`), `test/media_centaur_web/live/settings_live_social_test.exs` (two string assertions)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaurWeb.ProfileWordsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.ProfileWords

  test "every refusal a person-record form can meet has words" do
    assert ProfileWords.error(:name_required) == "A profile needs a name"
    assert ProfileWords.error(:name_too_long) == "Names are at most 50 characters"
    assert ProfileWords.error(:bad_image) == "That file is not a picture we can read"
    assert ProfileWords.error(:too_large) == "That picture cannot be made small enough"
    assert ProfileWords.error(:avatar_too_large) == ProfileWords.error(:too_large)
    assert ProfileWords.error(:invalid_hue) == "That colour cannot be used"
    assert ProfileWords.error(:too_many_profiles) == "Eight profiles is the most this install holds"
    assert ProfileWords.error(:last_profile) == "The last profile can't be removed"
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/profile_words_test.exs`
Expected: FAIL — `ProfileWords` undefined.

- [ ] **Step 3: Write the module and switch the social save to it**

`lib/media_centaur_web/profile_words.ex`:

```elixir
defmodule MediaCentaurWeb.ProfileWords do
  @moduledoc """
  The words for what a person-record form refused — a viewer profile's
  card and the social profile's card share them, since they share the
  rules (`MediaCentaur.DisplayName`, `MediaCentaur.Hue`, the picture
  field). One place, so the two cards never say the same thing two ways.
  """

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Profiles

  @spec error(atom()) :: String.t()
  def error(:name_required), do: "A profile needs a name"
  def error(:name_too_long), do: "Names are at most #{DisplayName.max_length()} characters"
  def error(:bad_image), do: "That file is not a picture we can read"
  def error(:too_large), do: "That picture cannot be made small enough"
  def error(:avatar_too_large), do: error(:too_large)
  def error(:invalid_hue), do: "That colour cannot be used"
  def error(:too_many_profiles), do: "#{Profiles.max_profiles() |> number_word()} profiles is the most this install holds"
  def error(:last_profile), do: "The last profile can't be removed"

  defp number_word(8), do: "Eight"
  defp number_word(n), do: Integer.to_string(n)
end
```

In `settings_live.ex` add `alias MediaCentaurWeb.ProfileWords` and replace the social save handler's whole `else` block (the five `{:error, …} -> put_flash` clauses) with one clause:

```elixir
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, ProfileWords.error(reason))}
    end
```

In `test/media_centaur_web/live/settings_live_social_test.exs` change the two `"Your profile needs a name"` assertions to `"A profile needs a name"`.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/profile_words_test.exs test/media_centaur_web/live/settings_live_social_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: one ProfileWords for every person-record form"
```

---

### Task 6: `PictureField.consume_change/5` (one upload-to-master path)

**Files:**
- Modify: `lib/media_centaur_web/components/picture_field.ex`
- Modify: `lib/media_centaur_web/live/settings_live.ex` (delete `avatar_change/2`), `lib/media_centaur_web/live/apps_live.ex` (`save_banner/3` uses it)
- Test: `test/media_centaur_web/components/picture_field_test.exs` (append `change/2` tests)

- [ ] **Step 1: Write the failing pure test**

Append to `test/media_centaur_web/components/picture_field_test.exs` (create it with `use MediaCentaur.Case, async: true` and `alias MediaCentaurWeb.Components.PictureField` if absent):

```elixir
  describe "change/2 — what the consumed entries and a pending Remove mean" do
    test "a master wins over a pending Remove; nothing chosen is Remove or keep" do
      assert PictureField.change([{:new, "bytes"}], true) == {:ok, {:new, "bytes"}}
      assert PictureField.change([{:new, "bytes"}], false) == {:ok, {:new, "bytes"}}
      assert PictureField.change([], true) == {:ok, :none}
      assert PictureField.change([], false) == {:ok, :keep}
    end

    test "a file libvips could not open, or one over the cap, is refused whatever Remove says" do
      assert PictureField.change([:bad_image], true) == {:error, :bad_image}
      assert PictureField.change([:too_large], false) == {:error, :too_large}
    end
  end
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/picture_field_test.exs`
Expected: FAIL — `PictureField.change/2` undefined.

- [ ] **Step 3: Add `consume_change/5` and `change/2`; switch both callers**

Add to `lib/media_centaur_web/components/picture_field.ex` after `crop_from_params/1`:

```elixir
  @typedoc "What a save does with the picture: keep what is stored, remove it, or set the master bytes."
  @type change :: :keep | :none | {:new, binary()}

  @typedoc "The master to cut: a WebP under a byte cap (an avatar, a profile picture) or a JPEG (an app banner)."
  @type master :: {:webp, MediaCentaur.ImageFiles.size(), pos_integer()} | {:jpeg, MediaCentaur.ImageFiles.size()}

  @doc """
  The one upload-to-master path: drops rejected entries, consumes the
  chosen file into `master` cut at `crop` (else the centre), and reads
  the result with a pending Remove as `change/2` does. Returns the
  socket (consuming changes it) and the change or the refusal. The
  entry is consumed either way, so a file libvips cannot open leaves
  nothing pending.
  """
  @spec consume_change(Phoenix.LiveView.Socket.t(), atom(), master(), MediaCentaur.ImageFiles.crop() | nil, boolean()) ::
          {Phoenix.LiveView.Socket.t(), {:ok, change()} | {:error, :bad_image | :too_large}}
  def consume_change(socket, upload, master, crop, removed?) do
    socket = drop_rejected(socket, upload)

    masters =
      Phoenix.LiveView.consume_uploaded_entries(socket, upload, fn %{path: path}, _entry ->
        {:ok, cut(master, path, crop)}
      end)

    {socket, change(masters, removed?)}
  end

  @doc "The pure step behind `consume_change/5`: a cut master wins, else Remove means none, else keep."
  @spec change([{:new, binary()} | :bad_image | :too_large], boolean()) ::
          {:ok, change()} | {:error, :bad_image | :too_large}
  def change([:bad_image], _removed?), do: {:error, :bad_image}
  def change([:too_large], _removed?), do: {:error, :too_large}
  def change([{:new, bytes}], _removed?), do: {:ok, {:new, bytes}}
  def change([], true), do: {:ok, :none}
  def change([], false), do: {:ok, :keep}

  defp cut({:webp, size, cap}, path, crop) do
    case MediaCentaur.ImageFiles.webp_master(path, size, cap, crop: crop) do
      {:ok, bytes} -> {:new, bytes}
      {:error, :too_large} -> :too_large
      {:error, _reason} -> :bad_image
    end
  end

  defp cut({:jpeg, size}, path, crop) do
    case MediaCentaur.ImageFiles.jpeg_master(path, size, crop: crop) do
      {:ok, bytes} -> {:new, bytes}
      {:error, _reason} -> :bad_image
    end
  end
```

In `lib/media_centaur_web/live/settings_live.ex`, delete `defp avatar_change/2` and its comment, and make the social save handler read (the event keeps its name `save_profile` until Task 8 renames it with the template; `ProfileWords` is Task 5's). The name is checked *before* the upload is consumed, as before, so a name error leaves the chosen picture pending:

```elixir
  def handle_event("save_profile", %{"name" => name} = params, socket) do
    case Social.check_name(name) do
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, ProfileWords.error(reason))}

      {:ok, _name} ->
        {socket, change} =
          PictureField.consume_change(
            socket,
            :avatar,
            {:webp, {256, 256}, ProfileTranslation.max_avatar_bytes()},
            PictureField.crop_from_params(params),
            socket.assigns.avatar_removed?
          )

        with {:ok, avatar} <- change,
             {:ok, profile} <- Social.save_profile(name, avatar, socket.assigns.profile_hue) do
          {:noreply,
           socket
           |> assign(identity_npub: Identity.npub(), profile_name: profile.name, profile_hue: profile.hue)
           |> assign(own_person: Social.own_person(), avatar_removed?: false)
           |> put_flash(:info, "Profile saved")}
        else
          {:error, reason} -> {:noreply, put_flash(socket, :error, ProfileWords.error(reason))}
        end
    end
  end
```

`Social.save_profile/3` returns `:avatar_too_large`; `consume_change/5` returns `:too_large`; `ProfileWords.error/1` words both.

In `lib/media_centaur_web/live/apps_live.ex` make `save_banner/3` read:

```elixir
  defp save_banner(socket, app, crop) do
    {socket, change} =
      PictureField.consume_change(socket, :banner, {:jpeg, @banner_size}, crop, socket.assigns.banner_removed?)

    case change do
      {:ok, change} ->
        case Apps.change_banner(app, change) do
          :ok -> socket
          {:error, :not_manual} -> socket
        end

      {:error, :bad_image} ->
        put_flash(socket, :error, "Saved, but that file is not an image we can read")
    end
  end
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/picture_field_test.exs test/media_centaur_web/live/settings_live_social_test.exs test/media_centaur_web/live/apps_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: one upload-to-master path in PictureField for avatar, banner and profile picture"
```

---

### Task 7: The identity tile draws any person from three facts

**Files:**
- Modify: `lib/media_centaur_web/components/social/identity_tile.ex`
- Modify: callers — `lib/media_centaur_web/components/detail_panel.ex:643`, `components/social/person_card.ex:99`, `components/social/feed_row.ex:71`, `components/title/social.ex:161`, `live/settings_live/social_section.ex:110`
- Modify: `storybook/social/identity_tile.story.exs`; Create: `storybook/social/crop_previews.story.exs`; Modify: `storybook/social/_social.index.exs`
- Test: `test/media_centaur_web/components/social/identity_tile_test.exs` (rewrite)

- [ ] **Step 1: Edit the story first (storybook-first)**

Replace `storybook/social/identity_tile.story.exs` with:

```elixir
defmodule MediaCentaurWeb.Storybook.Social.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046, UIDR-047, UIDR-053) from
  three facts — the name, the picture, the hue — and whether the person
  is of this install (filled) or a friend (tinted). The marks: the
  picture, else the first letter of the name, else the person glyph for
  a friend with no name at all. Four sizes: 32 in the title detail's
  social panel and lead review, 40 on a Feed row, the rail's person
  card and the sidebar's profile switcher, 48 on the Friends page's card
  and the Settings cards, 96 on the "Who's watching?" picker. The last
  group is the palette (UIDR-048).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Hue

  def function, do: &MediaCentaurWeb.Components.Social.IdentityTile.identity_tile/1
  def render_source, do: :function

  @photo "/images/storybook/sample-poster.jpg"

  def variations do
    [
      %VariationGroup{id: :panel_32, description: "32px: the social panel and the lead review", variations: states(32)},
      %VariationGroup{id: :row_40, description: "40px: a Feed row, the rail card, the sidebar switcher", variations: states(40)},
      %VariationGroup{id: :card_48, description: "48px: the Friends page's card and the Settings cards", variations: states(48)},
      %VariationGroup{
        id: :picker_96,
        description: "96px: a profile on the picker — always filled, never the glyph (a profile's name is required)",
        variations: [
          %Variation{id: :letter, attributes: %{name: "Ana", hue: 150, own?: true, size: 96}},
          %Variation{id: :picture, attributes: %{name: "Ana", picture_url: @photo, hue: 150, own?: true, size: 96}}
        ]
      },
      %VariationGroup{
        id: :hues,
        description:
          "The palette (UIDR-048): a friend's letter at every hue, then a filled tile at every hue, then a picture ringed in the hue; the first tile has no hue and is the default Blue",
        variations:
          [%Variation{id: :none, attributes: %{name: "Cleo", size: 48}}] ++
            for {name, hue} <- Hue.palette() do
              %Variation{id: String.to_atom("friend_" <> String.downcase(name)), description: "#{name} #{hue}", attributes: %{name: "Cleo", hue: hue, size: 48}}
            end ++
            for {name, hue} <- Hue.palette() do
              %Variation{id: String.to_atom("own_" <> String.downcase(name)), attributes: %{name: "You", hue: hue, own?: true, size: 48}}
            end ++
            [
              %Variation{id: :picture_teal, attributes: %{name: "Ada", picture_url: @photo, hue: 195, size: 48}},
              %Variation{id: :own_picture_violet, attributes: %{name: "You", picture_url: @photo, hue: 290, own?: true, size: 48}}
            ]
      }
    ]
  end

  defp states(size) do
    [
      %Variation{id: :letter, description: "A friend: the first letter of the name, in the default Blue on its tint", attributes: %{name: "Cleo", size: size}},
      %Variation{id: :glyph, description: "A friend with no name at all: the person glyph, never a letter", attributes: %{size: size}},
      %Variation{id: :picture, description: "A friend with a picture: inside a 1px ring in the hue", attributes: %{name: "Ada", picture_url: @photo, size: size}},
      %Variation{id: :own, description: "A person of this install: filled in the hue, the letter near-white", attributes: %{name: "You", own?: true, size: size}},
      %Variation{id: :own_picture, description: "A person of this install with a picture: a 2px ring", attributes: %{name: "You", picture_url: @photo, own?: true, size: size}}
    ]
  end
end
```

Create `storybook/social/crop_previews.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Social.CropPreviews do
  @moduledoc """
  The crop stage's two preview frames (*How it will look*): the filled
  tile's picture recipe at 48 and 40, each holding the canvas the
  `ImageCrop` hook paints. Empty here, since no hook runs in the catalog.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Social.IdentityTile.crop_previews/1
  def render_source, do: :function

  def variations do
    [
      %Variation{id: :frames, attributes: %{}},
      %Variation{id: :in_a_hue, description: "The hue rides the enclosing field's root and reaches the frames by inheritance", attributes: %{}, template: ~s|<div style="--hue: 195"><.psb-variation/></div>|}
    ]
  end
end
```

Add to `storybook/social/_social.index.exs`: `def entry("crop_previews"), do: [icon: {:fa, "crop", :thin}, name: "Crop previews"]`.

- [ ] **Step 2: Rewrite the tile test**

Replace `test/media_centaur_web/components/social/identity_tile_test.exs` with:

```elixir
defmodule MediaCentaurWeb.Components.Social.IdentityTileTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.SocialRows, only: [person: 1, person: 2, own_person: 0]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Social.IdentityTile

  defp render(attrs), do: LazyHTML.from_fragment(render_component(&IdentityTile.identity_tile/1, attrs))
  defp tile(html), do: LazyHTML.query(html, "[data-component='identity-tile']")
  defp letter(html), do: html |> tile() |> LazyHTML.text() |> String.trim()
  defp mark(html), do: html |> tile() |> LazyHTML.attribute("data-mark")

  test "a name is its monogram, hidden from assistive tech, tinted for a friend" do
    html = render(name: "cleo", size: 40)
    assert letter(html) == "C"
    assert mark(html) == ["letter"]
    assert html |> tile() |> LazyHTML.attribute("aria-hidden") == ["true"]
    assert html |> tile() |> LazyHTML.attribute("data-own") == []
    assert html |> tile() |> LazyHTML.attribute("data-size") == ["40"]
  end

  test "own? fills the tile" do
    html = render(name: "You", own?: true, size: 48)
    assert html |> LazyHTML.query("[data-component='identity-tile'][data-own]") |> Enum.count() == 1
    assert letter(html) == "Y"
  end

  test "a picture replaces the letter and paints eagerly" do
    html = render(name: "Ada", picture_url: "/images/storybook/sample-poster.jpg", size: 48)
    img = LazyHTML.query(html, "[data-component='identity-tile'] img")
    assert mark(html) == ["avatar"]
    assert LazyHTML.attribute(img, "src") == ["/images/storybook/sample-poster.jpg"]
    assert LazyHTML.attribute(img, "loading") == ["eager"]
    assert letter(html) == ""
  end

  test "no name at all is the person glyph, never a letter" do
    html = render(size: 40)
    assert mark(html) == ["glyph"]
    assert html |> LazyHTML.query("[data-component='identity-tile'] .hero-user-solid") |> Enum.count() == 1
  end

  test "the hue rides as --hue; none sets no style" do
    none = render(name: "cleo", size: 40)
    assert none |> tile() |> LazyHTML.attribute("style") == []
    some = render(name: "cleo", hue: 195, size: 40)
    assert some |> tile() |> LazyHTML.attribute("style") == ["--hue: 195"]
    assert some |> tile() |> LazyHTML.attribute("data-hue") == ["195"]
  end

  test "96 is the picker's size" do
    assert render(name: "Ana", own?: true, size: 96) |> tile() |> LazyHTML.attribute("data-size") == ["96"]
  end

  describe "person_attrs/1 — a Social.Person as the tile's facts" do
    test "a friend: the name the reader sees, the avatar, the resolved hue, tinted" do
      attrs = IdentityTile.person_attrs(person("cleo", avatar_url: "/a.webp", published_hue: 12, hue_override: 195))
      assert attrs == [name: "cleo", picture_url: "/a.webp", hue: 195, own?: false]
    end

    test "a friend with no name at all passes nil, so the glyph is drawn" do
      assert IdentityTile.person_attrs(person(nil))[:name] == nil
    end

    test "the reader's own takes You and is filled" do
      attrs = IdentityTile.person_attrs(own_person())
      assert attrs[:name] == "You"
      assert attrs[:own?] == true
    end
  end
end
```

- [ ] **Step 3: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/social/identity_tile_test.exs`
Expected: FAIL — `person` is a required attr / `person_attrs/1` undefined.

- [ ] **Step 4: Widen the component**

Replace the attrs, the function and the private marks in `lib/media_centaur_web/components/social/identity_tile.ex`:

```elixir
  attr :name, :string, default: nil, doc: "the words the surface shows for the person (You for the reader's own); nil only for a friend with no name at all"
  attr :picture_url, :string, default: nil, doc: "the picture's versioned URL, or nil for none"
  attr :hue, :integer, default: nil, doc: "the hue the tile draws in (UIDR-048); nil draws the default Blue"
  attr :own?, :boolean, default: false, doc: "a person of this install — the reader, a profile — filled in the hue; a friend is tinted"
  attr :size, :integer, required: true, values: [32, 40, 48, 96]

  def identity_tile(assigns) do
    assigns =
      assign(assigns,
        size_classes: size_classes(assigns.size),
        glyph_classes: glyph_classes(assigns.size),
        mark: mark(assigns.picture_url, assigns.name)
      )

    ~H"""
    <span
      class={[
        "identity-tile relative grid shrink-0 place-items-center overflow-hidden rounded-full leading-none",
        @size_classes,
        if(@own?, do: "identity-tile-own font-bold", else: "identity-tile-friend font-semibold"),
        @mark == :avatar && "identity-tile-avatar"
      ]}
      {hue_style(@hue)}
      data-component="identity-tile"
      data-size={@size}
      data-own={@own?}
      data-mark={@mark}
      data-hue={@hue}
      aria-hidden="true"
    >
      <img :if={@mark == :avatar} src={@picture_url} alt="" class="size-full object-cover" loading="eager" decoding="sync" />
      <.icon :if={@mark == :glyph} name="hero-user-solid" class={@glyph_classes} />
      {if @mark == :letter, do: Format.monogram(@name)}
    </span>
    """
  end

  @doc """
  The tile's attrs for a `Social.Person` (ADR-074): the words the reader
  sees (`Format.person_name/1` for their own, so the tile takes the Y of
  You; the resolved name, else nil, for a friend), the avatar, the
  resolved hue, and the own flag. Spread it: `<.identity_tile {person_attrs(person)} size={40} />`.
  """
  @spec person_attrs(Person.t()) :: keyword()
  def person_attrs(%Person{} = person) do
    [name: person_words(person), picture_url: person.avatar_url, hue: Person.hue(person), own?: person.own?]
  end

  @doc """
  The crop stage's two preview frames (`PictureField`'s `:preview`
  slot, *How it will look*): the filled tile's picture recipe at 48 and
  40, each holding the canvas the `ImageCrop` hook paints. The hue
  reaches them from the enclosing field's root.
  """
  def crop_previews(assigns) do
    ~H"""
    <span
      :for={size <- [48, 40]}
      class={["identity-tile identity-tile-own identity-tile-avatar relative grid shrink-0 place-items-center overflow-hidden rounded-full", size_classes(size)]}
      aria-hidden="true"
    >
      <canvas data-role="preview" width={size} height={size} class="size-full"></canvas>
    </span>
    """
  end

  defp person_words(%Person{own?: true} = person), do: Format.person_name(person)
  defp person_words(%Person{} = person), do: Person.name(person)

  defp mark(url, _name) when is_binary(url), do: :avatar
  defp mark(_url, name) when is_binary(name) and name != "", do: :letter
  defp mark(_url, _name), do: :glyph
```

Extend the size clauses:

```elixir
  defp size_classes(32), do: "size-8 text-sm"
  defp size_classes(40), do: "size-10 text-base"
  defp size_classes(48), do: "size-12 text-[19px]"
  defp size_classes(96), do: "size-24 text-[38px]"

  defp glyph_classes(32), do: "size-4"
  defp glyph_classes(40), do: "size-5"
  defp glyph_classes(48), do: "size-6"
  defp glyph_classes(96), do: "size-12"
```

Update the moduledoc's first paragraph to say the tile draws from the three facts and `own?`, adds 96 for the picker, and that `person_attrs/1` is how a `Social.Person` becomes them (UIDR-053 rule 4).

Switch the five callers:

```heex
<IdentityTile.identity_tile {IdentityTile.person_attrs(@note.author)} size={32} />          <%!-- detail_panel.ex --%>
<IdentityTile.identity_tile {IdentityTile.person_attrs(@person)} size={tile_size(@width)} />  <%!-- person_card.ex --%>
<IdentityTile.identity_tile {IdentityTile.person_attrs(@entry.author)} size={40} />          <%!-- feed_row.ex --%>
<IdentityTile.identity_tile {IdentityTile.person_attrs(review.author)} size={32} />          <%!-- title/social.ex --%>
```

In `social_section.ex` the `:current` slot becomes `<IdentityTile.identity_tile {IdentityTile.person_attrs(shown_person(@own_person, @avatar_removed?, @profile_hue))} size={48} />` and the whole `<:preview>` slot body becomes `<IdentityTile.crop_previews />`.

- [ ] **Step 5: Run the tests, the stories and the social tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/social/ test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/live/settings_live_social_test.exs test/media_centaur_web/live/social_live_test.exs`
Expected: PASS. Then start the dev server if it is not running and look at `/storybook/social/identity_tile` and `/storybook/social/crop_previews` with `page-shot --url http://127.0.0.1:2160/storybook/social/identity_tile --viewport 1920x1080 --wait-ms 3000`; the 96 group renders filled tiles.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: the identity tile draws any person from three facts; 96 for the picker (UIDR-053)"
```

---

### Task 8: The social profile card is "Social profile"

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live/social_section.ex`, `lib/media_centaur_web/live/settings_live.ex`
- Modify: `test/media_centaur_web/live/settings_live_social_test.exs`
- Modify: wiki `Settings-Reference.md`, `Social.md`, `Troubleshooting.md`

- [ ] **Step 1: Edit the test first**

In `test/media_centaur_web/live/settings_live_social_test.exs`:

```bash
sed -i 's/#profile-form/#social-profile-form/g; s/#profile-name/#social-profile-name/g; s/#profile-hues/#social-profile-hues/g; s/"Your profile"/"Social profile"/g; s/Your profile first/Social profile first/; s/"Profile saved"/"Social profile saved"/g' test/media_centaur_web/live/settings_live_social_test.exs
```

Check the `describe`/test names still read true (`grep -n "Your profile\|profile-form" test/media_centaur_web/live/settings_live_social_test.exs` prints nothing).

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_social_test.exs`
Expected: FAIL — `#social-profile-form` not found.

- [ ] **Step 3: Relabel the card and rename its ids and events**

In `social_section.ex`: the card's `title="Your profile"` → `title="Social profile"`; `id="profile-form"` → `id="social-profile-form"`; `phx-submit="save_profile"` → `"save_social_profile"`; `phx-change="validate_profile"` → `"validate_social_profile"`; `remove_event="remove_avatar"` → `"remove_social_avatar"`; `cancel_event="cancel_avatar"` → `"cancel_social_avatar"`; `id="profile-name"` → `"social-profile-name"`; `id="profile-hues"` → `"social-profile-hues"`; `event="set_profile_hue"` → `"set_social_profile_hue"`. The button stays "Save" / "Create profile" → make the create label "Create social profile". Update the moduledoc's "Your profile" to "Social profile" and the handler names it lists; `profile_description/1` keeps its words.

In `settings_live.ex` rename the six handler heads to match (`validate_social_profile` ×2, `set_social_profile_hue`, `remove_social_avatar`, `cancel_social_avatar`, `save_social_profile`) and the save's flash to "Social profile saved", and the section description at line ~130 to "Your social profile and identity, the relays your activity travels over, and what you share. Friends are managed on the Social page."

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_social_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: PASS.

- [ ] **Step 5: The wiki**

In `../media-centaur.wiki/` (the sibling repo; do not push, the owner does):
- `Settings-Reference.md` line 92: `**Your profile**` → `**Social profile**`.
- `Social.md` line 25: "type your name under **Your profile** and press **Create profile**" → "type your name under **Social profile** and press **Create social profile**".
- `Troubleshooting.md` line 183: "**Settings → Social → Your profile**" → "**Settings → Social → Social profile**".

Commit there with `git commit -am "wiki: the social profile card is Social profile"`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: Settings → Social's profile card is the social profile"
```

---

### Task 9: `ProfileAware` — the session hook and the sidebar switcher

**Files:**
- Create: `lib/media_centaur_web/live/profile_aware/logic.ex`, `lib/media_centaur_web/live/profile_aware.ex`
- Modify: `lib/media_centaur_web/router.ex` (on_mount list), `lib/media_centaur_web/components/layouts.ex` (attrs + switcher), the 12 LiveViews that call `<Layouts.app` (listed in step 5)
- Modify: `lib/media_centaur_web.ex` boundary deps (add `MediaCentaur.Profiles`)
- Modify: `test/support/conn_case.ex` (`with_profile/2`)
- Test: `test/media_centaur_web/live/profile_aware/logic_test.exs`, `test/media_centaur_web/live/profile_aware_test.exs`

- [ ] **Step 1: Write the failing pure test**

`test/media_centaur_web/live/profile_aware/logic_test.exs`:

```elixir
defmodule MediaCentaurWeb.Live.ProfileAware.LogicTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Profiles.Profile
  alias MediaCentaurWeb.Live.ProfileAware.Logic

  @me %Profile{id: "11111111-1111-4111-8111-111111111111", name: "Me"}
  @ana %Profile{id: "22222222-2222-4222-8222-222222222222", name: "Ana"}

  test "one profile is active whatever the cookie says" do
    assert Logic.resolve(nil, [@me]) == {:active, @me}
    assert Logic.resolve("stale", [@me]) == {:active, @me}
  end

  test "with more than one, the cookie names the active profile; none or a stale one asks" do
    assert Logic.resolve(@ana.id, [@me, @ana]) == {:active, @ana}
    assert Logic.resolve(nil, [@me, @ana]) == :pick
    assert Logic.resolve("gone", [@me, @ana]) == :pick
  end

  test "no profiles at all asks" do
    assert Logic.resolve(nil, []) == :pick
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/profile_aware/logic_test.exs`
Expected: FAIL — `Logic` undefined.

- [ ] **Step 3: Write `Logic` and the hook**

`lib/media_centaur_web/live/profile_aware/logic.ex`:

```elixir
defmodule MediaCentaurWeb.Live.ProfileAware.Logic do
  @moduledoc "The pure rule behind `ProfileAware`: which profile a session is using, or that it must pick (UIDR-053)."

  alias MediaCentaur.Profiles.Profile

  @doc "The one profile; else the one the cookie names; else `:pick`."
  @spec resolve(String.t() | nil, [Profile.t()]) :: {:active, Profile.t()} | :pick
  def resolve(_cookie, [profile]), do: {:active, profile}

  def resolve(cookie, profiles) when is_binary(cookie) do
    case Enum.find(profiles, &(&1.id == cookie)) do
      nil -> :pick
      profile -> {:active, profile}
    end
  end

  def resolve(_cookie, _profiles), do: :pick
end
```

`lib/media_centaur_web/live/profile_aware.ex`:

```elixir
defmodule MediaCentaurWeb.Live.ProfileAware do
  @moduledoc """
  The `on_mount` hook that says who is watching (ADR-078, UIDR-053), one
  entry in `live_session :default`'s list. The active profile is the
  `"profile_id"` key of the signed session, set by `ProfileController`;
  `Logic.resolve/2` turns it and `Profiles.list/0` into the active
  profile, or `:pick`, on which the first `handle_params` redirects to
  the picker with the page's own URL as `return_to`. With one profile
  the cookie is never consulted and no picker exists.

  Assigns `:profile` (the active `Profiles.Profile`) and `:profiles`
  (every profile, for the switcher's presence and Settings → Profiles),
  subscribes to `profiles:updates` through the subscribe door, and on
  any profile event re-reads the list: a renamed active profile is
  re-assigned, a removed one drops the session to the picker. The hook
  halts those messages — no page handles them itself.
  """

  use MediaCentaurWeb, :verified_routes

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias MediaCentaur.Profiles
  alias MediaCentaurWeb.Live.ProfileAware.Logic
  alias MediaCentaurWeb.Live.Subscriptions

  @profile_events [:profile_added, :profile_changed, :profile_removed]

  def on_mount(:default, _params, session, socket) do
    profiles = Profiles.list()

    case Logic.resolve(session["profile_id"], profiles) do
      {:active, profile} ->
        {:cont,
         socket
         |> assign(profile: profile, profiles: profiles)
         |> Subscriptions.subscribe(Profiles)
         |> attach_hook(:profile_aware, :handle_info, &on_profiles_event/2)}

      :pick ->
        {:cont, attach_hook(socket, :profile_aware_pick, :handle_params, &redirect_to_picker/3)}
    end
  end

  defp redirect_to_picker(_params, uri, socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    return_to = if query, do: path <> "?" <> query, else: path
    {:halt, redirect(socket, to: ~p"/profiles?return_to=#{return_to}")}
  end

  defp on_profiles_event({tag, _event}, socket) when tag in @profile_events do
    profiles = Profiles.list()

    case Enum.find(profiles, &(&1.id == socket.assigns.profile.id)) do
      nil -> {:halt, redirect(socket, to: ~p"/profiles")}
      profile -> {:halt, assign(socket, profile: profile, profiles: profiles)}
    end
  end

  defp on_profiles_event(_message, socket), do: {:cont, socket}
end
```

In `lib/media_centaur_web/router.ex` add, right after `MediaCentaurWeb.Live.ArmGesture,` in the `on_mount` list:

```elixir
        # Who is watching (ADR-078): assigns :profile and :profiles, or
        # redirects the first handle_params to the picker.
        MediaCentaurWeb.Live.ProfileAware,
```

In `lib/media_centaur_web.ex` add `MediaCentaur.Profiles,` to the `use Boundary` deps list (alphabetical neighbours do not matter; the list is not sorted).

- [ ] **Step 4: Write the failing hook test**

`test/media_centaur_web/live/profile_aware_test.exs`:

```elixir
defmodule MediaCentaurWeb.Live.ProfileAwareTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Profiles

  # /guide is the lightest page under live_session :default.
  @page "/guide"

  test "one profile: every page mounts with it and no switcher", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @page)
    assert render(view) =~ "Guide"
    refute has_element?(view, "#sidebar-profile")
  end

  test "two profiles and no cookie: the first page redirects to the picker with the page as return_to", %{conn: conn} do
    create_profile(name: "Ana")
    assert {:error, {:redirect, %{to: "/profiles?return_to=%2Fguide"}}} = live(conn, @page)
    assert {:error, {:redirect, %{to: "/profiles?return_to=%2Fsettings%3Fsection%3Dtmdb"}}} = live(conn, "/settings?section=tmdb")
  end

  test "two profiles and a cookie: the named profile is active and the switcher shows it", %{conn: conn} do
    ana = create_profile(name: "Ana")
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!(@page)
    assert has_element?(view, "#sidebar-profile", "Ana")
  end

  test "a stale cookie asks again", %{conn: conn} do
    create_profile(name: "Ana")
    conn = Plug.Test.init_test_session(conn, %{"profile_id" => Ecto.UUID.generate()})
    assert {:error, {:redirect, %{to: "/profiles?return_to=%2Fguide"}}} = live(conn, @page)
  end

  test "a rename reaches the open page; removing the active profile drops it to the picker", %{conn: conn} do
    ana = create_profile(name: "Ana")
    {:ok, view, _html} = conn |> with_profile(ana) |> live_async!(@page)

    {:ok, ana} = Profiles.rename(ana, "Anna")
    render_until(view, fn _html -> has_element?(view, "#sidebar-profile", "Anna") end)

    :ok = Profiles.remove(ana)
    assert_redirect(view, "/profiles")
  end
end
```

Add to `test/support/conn_case.ex` after `enable_tmdb!/0`:

```elixir
  @doc "Picks a viewer profile for the connection's session, as the activate route does."
  def with_profile(conn, %MediaCentaur.Profiles.Profile{id: id}),
    do: Plug.Test.init_test_session(conn, %{"profile_id" => id})
```

and `import MediaCentaur.TestFactory` to the `using` block's imports if `create_profile/1` is not reachable (ConnCase does not import the factory today; add `import MediaCentaur.TestFactory` beside `import MediaCentaur.Eventually`).

- [ ] **Step 5: Run it to see it fail, then add the switcher and the attrs**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/profile_aware_test.exs`
Expected: the redirect tests PASS, the switcher tests FAIL (no `#sidebar-profile`).

In `lib/media_centaur_web/components/layouts.ex` add after the `attr :show_apps` block:

```elixir
  attr :profile, MediaCentaur.Profiles.Profile, required: true, doc: "the session's active profile (`Live.ProfileAware`)"
  attr :profiles, :list, required: true, doc: "every profile; the switcher shows only with more than one"
```

and `alias MediaCentaur.Profiles` and `alias MediaCentaurWeb.Components.Social.IdentityTile` at the top. Insert as the first child of `<aside id="sidebar" …>`, before the "Watch" group label:

```heex
        <%!-- The profile switcher (UIDR-053 rule 3): the active profile's
              tile and name, a link to the picker; present only when there is
              someone to switch to. --%>
        <.link
          :if={length(@profiles) > 1}
          id="sidebar-profile"
          navigate={~p"/profiles"}
          class="sidebar-link mb-3"
          data-tip="Switch profile"
          data-nav-item
          tabindex="0"
        >
          <IdentityTile.identity_tile
            name={@profile.name}
            picture_url={Profiles.picture_url(@profile)}
            hue={@profile.hue}
            own?
            size={32}
          />
          <span class="sidebar-label truncate">{@profile.name}</span>
        </.link>
```

Then in each of these 12 files add `profile={@profile}` and `profiles={@profiles}` to the `<Layouts.app` call (two attributes, anywhere among the existing ones): `guide_live.ex`, `review_live.ex`, `episode_mapping_live.ex`, `console_page_live.ex`, `home_live.ex`, `social_live.ex`, `settings_live.ex`, `library_live.ex`, `status_live.ex`, `apps_live.ex`, `watch_history_live.ex`, `incoming_live.ex` (all under `lib/media_centaur_web/live/`). Compile with `~/scripts/agents/agent-mix compile --warnings-as-errors`: a missed call site is a "missing required attribute" warning.

- [ ] **Step 6: Run the hook tests and the page smoke**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/profile_aware_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: the session holds the active profile; ProfileAware and the sidebar switcher (ADR-078)"
```

---

### Task 10: `ProfileController` — the activate route

**Files:**
- Create: `lib/media_centaur_web/controllers/profile_controller/return_to.ex`, `lib/media_centaur_web/controllers/profile_controller.ex`
- Modify: `lib/media_centaur_web/router.ex`
- Test: `test/media_centaur_web/controllers/profile_controller/return_to_test.exs`, `test/media_centaur_web/controllers/profile_controller_test.exs`

- [ ] **Step 1: Write the failing tests**

`test/media_centaur_web/controllers/profile_controller/return_to_test.exs`:

```elixir
defmodule MediaCentaurWeb.ProfileController.ReturnToTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.ProfileController.ReturnTo

  test "a local path returns; anything else, the picker itself included, goes home" do
    assert ReturnTo.local_path("/library") == "/library"
    assert ReturnTo.local_path("/settings?section=tmdb") == "/settings?section=tmdb"
    assert ReturnTo.local_path("/") == "/"
    assert ReturnTo.local_path(nil) == "/"
    assert ReturnTo.local_path("") == "/"
    assert ReturnTo.local_path("//evil.example") == "/"
    assert ReturnTo.local_path("/\\evil.example") == "/"
    assert ReturnTo.local_path("https://evil.example/") == "/"
    assert ReturnTo.local_path("/profiles") == "/"
    assert ReturnTo.local_path("/profiles?return_to=%2Flibrary") == "/"
  end
end
```

`test/media_centaur_web/controllers/profile_controller_test.exs`:

```elixir
defmodule MediaCentaurWeb.ProfileControllerTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory

  test "activating a profile writes it to the session and returns to the page", %{conn: conn} do
    ana = create_profile(name: "Ana")
    conn = post(conn, ~p"/profiles/#{ana.id}/activate", %{"return_to" => "/library"})
    assert redirected_to(conn) == "/library"
    assert get_session(conn, "profile_id") == ana.id
  end

  test "an unknown or malformed id goes back to the picker and writes nothing", %{conn: conn} do
    conn = post(conn, ~p"/profiles/#{Ecto.UUID.generate()}/activate", %{})
    assert redirected_to(conn) == "/profiles"
    assert get_session(conn, "profile_id") == nil

    conn = post(build_conn(), "/profiles/not-a-uuid/activate", %{})
    assert redirected_to(conn) == "/profiles"
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/controllers/profile_controller/return_to_test.exs test/media_centaur_web/controllers/profile_controller_test.exs`
Expected: FAIL — `ReturnTo` undefined; no route matches.

- [ ] **Step 3: Write the two modules and the route**

`lib/media_centaur_web/controllers/profile_controller/return_to.ex`:

```elixir
defmodule MediaCentaurWeb.ProfileController.ReturnTo do
  @moduledoc """
  The one guard on where the activate route sends the browser next: a
  path on this app, never a URL, never the picker itself (which would
  ask the question that was just answered).
  """

  @spec local_path(term()) :: String.t()
  def local_path("/profiles" <> _rest), do: "/"
  def local_path(<<"/", next, _::binary>> = path) when next != ?/ and next != ?\\, do: path
  def local_path(_other), do: "/"
end
```

`lib/media_centaur_web/controllers/profile_controller.ex`:

```elixir
defmodule MediaCentaurWeb.ProfileController do
  @moduledoc """
  Sets the session's active profile (ADR-078): the picker's tiles post
  here, since a LiveView cannot write a cookie. Writes `"profile_id"`
  into the signed session and returns to `return_to` under
  `ReturnTo.local_path/1`. An unknown id goes back to the picker.
  """

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Profiles
  alias MediaCentaurWeb.ProfileController.ReturnTo

  def activate(conn, %{"id" => id} = params) do
    case Profiles.get(id) do
      nil ->
        redirect(conn, to: ~p"/profiles")

      profile ->
        conn
        |> put_session("profile_id", profile.id)
        |> redirect(to: ReturnTo.local_path(params["return_to"]))
    end
  end
end
```

In `router.ex`, inside `scope "/", MediaCentaurWeb do … pipe_through :browser`, after the `live_session :default` block:

```elixir
    # The picker's tiles post here: a LiveView cannot write the session cookie.
    post "/profiles/:id/activate", ProfileController, :activate
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/controllers/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: POST /profiles/:id/activate writes the session's active profile"
```

---

### Task 11: `ProfilesLive` — "Who's watching?"

**Files:**
- Create: `lib/media_centaur_web/live/profiles_live.ex`
- Modify: `lib/media_centaur_web/router.ex` (`live_session :profiles`)
- Create: `assets/js/input/profiles_behavior.js`, `assets/js/input/__tests__/profiles_behavior.test.js`
- Modify: `assets/js/input/config.js`, `assets/js/input/page_behavior.js`
- Modify: `test/media_centaur_web/page_smoke_test.exs`
- Test: `test/media_centaur_web/live/profiles_live_test.exs`

- [ ] **Step 1: Write the failing LiveView test**

`test/media_centaur_web/live/profiles_live_test.exs`:

```elixir
defmodule MediaCentaurWeb.ProfilesLiveTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import Phoenix.LiveViewTest

  alias MediaCentaur.Profiles

  test "asks who is watching with a tile per profile that posts to the activate route", %{conn: conn} do
    ana = create_profile(name: "Ana")
    [me, _ana] = Profiles.list()
    {:ok, view, html} = live(conn, "/profiles?return_to=/library")

    assert html =~ "Who's watching?"
    assert has_element?(view, "#pick-#{me.id} button", "Me")
    assert has_element?(view, "#pick-#{ana.id} button", "Ana")
    assert has_element?(view, "#pick-#{ana.id}[action='/profiles/#{ana.id}/activate'][method='post']")
    assert has_element?(view, "#pick-#{ana.id} input[name='return_to'][value='/library']")

    conn = view |> form("#pick-#{ana.id}") |> submit_form(conn)
    assert redirected_to(conn) == "/library"
    assert get_session(conn, "profile_id") == ana.id
  end

  test "adds a profile inline and shows the new tile; a blank name says why", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/profiles")

    view |> form("#add-profile-form", %{"name" => "   "}) |> render_submit()
    assert render(view) =~ "A profile needs a name"
    assert Profiles.count() == 1

    view |> form("#add-profile-form", %{"name" => "Ana"}) |> render_submit()
    assert Profiles.count() == 2
    [_me, ana] = Profiles.list()
    render_until(view, fn _html -> has_element?(view, "#pick-#{ana.id} button", "Ana") end)
  end

  test "at the cap there is no add form", %{conn: conn} do
    for n <- 2..8, do: create_profile(name: "Person #{n}")
    {:ok, view, _html} = live(conn, "/profiles")
    refute has_element?(view, "#add-profile-form")
  end
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/profiles_live_test.exs`
Expected: FAIL — no route for `/profiles`.

- [ ] **Step 3: The LiveView and its route**

`lib/media_centaur_web/live/profiles_live.ex`:

```elixir
defmodule MediaCentaurWeb.ProfilesLive do
  @moduledoc """
  The picker at `/profiles` (UIDR-053): "Who's watching?" over a tile
  per profile and, under the cap, an inline Add. A tile is a plain form
  posting to `ProfileController.activate/2` with `return_to`, since the
  session cookie is the controller's to write; the input system
  activates its button like any other on SELECT. Sidebar-less, in its
  own `live_session :profiles` so `ProfileAware` does not run here.
  Subscribes to `profiles:updates` so a profile added from Settings
  shows at once.
  """

  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.Components.Settings, only: [settings_input: 1]

  alias MediaCentaur.Profiles
  alias MediaCentaurWeb.Components.Social.IdentityTile
  alias MediaCentaurWeb.Live.Subscriptions
  alias MediaCentaurWeb.ProfileController.ReturnTo
  alias MediaCentaurWeb.ProfileWords

  @profile_events [:profile_added, :profile_changed, :profile_removed]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Who's watching?", profiles: [], return_to: "/", add_error: nil)
     |> Subscriptions.subscribe(Profiles)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, profiles: Profiles.list(), return_to: ReturnTo.local_path(params["return_to"]))}
  end

  @impl true
  def handle_event("add_profile", %{"name" => name}, socket) do
    case Profiles.add(name) do
      {:ok, _profile} -> {:noreply, assign(socket, add_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, add_error: ProfileWords.error(reason))}
    end
  end

  @impl true
  def handle_info({tag, _event}, socket) when tag in @profile_events,
    do: {:noreply, assign(socket, profiles: Profiles.list())}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.input_system_root class="relative min-h-viewport">
      <div class="page-side-dim page-side-dim-calm" aria-hidden="true"></div>
      <div
        class="relative z-[1] flex min-h-viewport flex-col items-center justify-center gap-12 px-4 py-16"
        data-page-behavior="profiles"
        data-nav-default-zone="profiles"
      >
        <h1 class="text-3xl font-semibold">Who's watching?</h1>
        <div id="profile-picker" class="flex flex-wrap items-start justify-center gap-10" data-nav-zone="grid">
          <.form
            :for={profile <- @profiles}
            for={%{}}
            as={:pick}
            id={"pick-#{profile.id}"}
            action={~p"/profiles/#{profile.id}/activate"}
            method="post"
            class="contents"
          >
            <input type="hidden" name="return_to" value={@return_to} />
            <button
              type="submit"
              class="flex w-36 cursor-pointer flex-col items-center gap-3 rounded-xl p-3"
              data-nav-item
              tabindex="0"
            >
              <IdentityTile.identity_tile
                name={profile.name}
                picture_url={Profiles.picture_url(profile)}
                hue={profile.hue}
                own?
                size={96}
              />
              <span class="max-w-full truncate text-base">{profile.name}</span>
            </button>
          </.form>
          <form
            :if={length(@profiles) < Profiles.max_profiles()}
            id="add-profile-form"
            phx-submit="add_profile"
            class="flex w-36 flex-col items-center gap-3 p-3"
          >
            <.settings_input
              name="name"
              placeholder="Add profile"
              maxlength={MediaCentaur.DisplayName.max_length()}
              autocomplete="off"
              class="w-full text-center"
              data-nav-item
              tabindex="0"
            />
            <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">Add</.button>
            <p :if={@add_error} class="text-xs text-error">{@add_error}</p>
          </form>
        </div>
      </div>
    </Layouts.input_system_root>
    """
  end
end
```

In `router.ex`, after the `live_session :default … end` block and before the `post`:

```elixir
    # The picker runs without ProfileAware: it is where a session with no
    # active profile is sent, so it cannot require one.
    live_session :profiles do
      live "/profiles", ProfilesLive, :index
    end
```

- [ ] **Step 4: The input system**

`assets/js/input/profiles_behavior.js`:

```js
/**
 * Profile picker page behavior ("Who's watching?", UIDR-053): a sidebar-less
 * page with one `grid` zone holding the profile tiles and the add form. There
 * is deliberately NO `activateOnFocus` — a tile submits the form that switches
 * the profile, so it must fire only on an explicit SELECT, never because the
 * cursor passed over it. BACK is a no-op (there is no sidebar to exit to).
 *
 * @returns {import("./page_behavior").PageBehavior}
 */
export function createProfilesBehavior() {
  return {
    onAttach() {},
    onDetach() {},
  }
}
```

In `assets/js/input/page_behavior.js` add `import { createProfilesBehavior } from "./profiles_behavior"` beside the setup import and `profiles: () => createProfilesBehavior(),` after the `setup:` entry.

In `assets/js/input/config.js` add after the `setup:` layout:

```js
    // Profile picker: one grid of tiles and the add form, no sidebar.
    profiles: {
      grid: {},
    },
```

and after `setup:     ["grid"],` in `cursorStartPriority`: `profiles:  ["grid"],`.

`assets/js/input/__tests__/profiles_behavior.test.js`:

```js
import { describe, expect, test } from "bun:test"
import { createProfilesBehavior } from "../profiles_behavior"

describe("profiles behavior", () => {
  test("does not activate items on focus — a tile switches the profile only on an explicit SELECT", () => {
    const behavior = createProfilesBehavior()
    expect(behavior.activateOnFocus ?? []).toEqual([])
  })

  test("defines no onEscape — the picker has no sidebar to exit to", () => {
    const behavior = createProfilesBehavior()
    expect(behavior.onEscape).toBeUndefined()
  })
})
```

Run: `bun test assets/js/input/`
Expected: all pass, `config_coverage` included (it reads the new template's `data-page-behavior="profiles"` and `data-nav-default-zone="profiles"`).

- [ ] **Step 5: Page smoke**

In `test/media_centaur_web/page_smoke_test.exs` add `{"/profiles", "profile picker"},` to the top-level route list.

- [ ] **Step 6: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/profiles_live_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: PASS.

- [ ] **Step 7: Verify the real post in a browser**

The LiveView test skips CSRF, so the real form must be exercised once. With the dev server running and a second profile added (`~/scripts/agents/mc-eval 'MediaCentaur.Profiles.add("Ana")'`):

```bash
~/scripts/agents/page-shot --url http://127.0.0.1:2160/profiles --viewport 1920x1080 --wait-ms 3000
~/scripts/agents/chromium-probe --with-console http://127.0.0.1:2160/profiles 'document.querySelector("#profile-picker form button").click(); new Promise(r => setTimeout(() => r(location.pathname), 1500))'
```

Expected: the screenshot shows the two tiles and the add form; the probe resolves to `/` (the redirect landed, so the CSRF token was accepted). Read the PNG. If the probe lands on `/profiles` with a 403 in the console, the form's `_csrf_token` is missing: `Phoenix.Component.form/1` with `method="post"` adds it — check the rendered HTML has the hidden input.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: the Who's watching? picker at /profiles (UIDR-053)"
```

---

### Task 12: Settings → Profiles

**Files:**
- Create: `lib/media_centaur_web/live/settings_live/profiles_section.ex`
- Modify: `lib/media_centaur_web/live/settings_live.ex` (section entry, upload, assigns, handlers, dispatch)
- Modify: `test/media_centaur_web/page_smoke_test.exs` (section list)
- Test: `test/media_centaur_web/live/settings_live_profiles_test.exs`

- [ ] **Step 1: Write the failing test**

`test/media_centaur_web/live/settings_live_profiles_test.exs`:

```elixir
defmodule MediaCentaurWeb.SettingsLiveProfilesTest do
  use MediaCentaurWeb.ConnCase, async: false

  import MediaCentaur.TestFactory
  import MediaCentaur.TmpDataDir
  import Phoenix.LiveViewTest

  alias MediaCentaur.Profiles
  alias MediaCentaur.Profiles.PictureStore

  @section "/settings?section=profiles"

  setup :setup_tmp_data_dir

  defp card(id), do: "#profile-card-#{id}"

  test "one card per profile, Remove disabled on the last one, and an Add card", %{conn: conn} do
    [me] = Profiles.list()
    {:ok, view, _html} = live_async!(conn, @section)
    assert has_element?(view, "#{card(me.id)} h3", "Me")
    assert has_element?(view, "#remove-profile-#{me.id}[disabled]")
    assert has_element?(view, "#add-profile")
  end

  test "Add adds a card; the hook keeps the list live", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @section)
    view |> form("#settings-add-profile-form", %{"name" => "Ana"}) |> render_submit()
    [_me, ana] = Profiles.list()
    render_until(view, fn _html -> has_element?(view, "#{card(ana.id)} h3", "Ana") end)
    refute has_element?(view, "#remove-profile-#{ana.id}[disabled]")
  end

  test "the name saves on blur and on Enter; a blank one is refused in words", %{conn: conn} do
    [me] = Profiles.list()
    {:ok, view, _html} = live_async!(conn, @section)

    view |> element("#profile-name-#{me.id}") |> render_blur(%{"value" => " Sample Name "})
    assert %{name: "Sample Name"} = Profiles.get(me.id)

    view |> element("#profile-name-#{me.id}") |> render_keydown(%{"key" => "Enter", "value" => "Ana"})
    assert %{name: "Ana"} = Profiles.get(me.id)

    view |> element("#profile-name-#{me.id}") |> render_blur(%{"value" => "  "})
    assert render(view) =~ "A profile needs a name"
    assert %{name: "Ana"} = Profiles.get(me.id)
  end

  test "a swatch and the slider set the hue", %{conn: conn} do
    [me] = Profiles.list()
    {:ok, view, _html} = live_async!(conn, @section)

    view |> element("#profile-hues-#{me.id} button[data-hue='195']") |> render_click()
    assert %{hue: 195} = Profiles.get(me.id)

    view |> form("#profile-card-form-#{me.id}") |> render_change(%{"_target" => ["hue"], "hue" => "12", "id" => me.id})
    assert %{hue: 12} = Profiles.get(me.id)
  end

  test "a picture is chosen, cropped, saved, then removed", %{conn: conn, data_dir: data_dir} do
    [me] = Profiles.list()
    {:ok, view, _html} = live_async!(conn, @section)

    view |> element("#edit-profile-picture-#{me.id}") |> render_click()
    {:ok, png} = Image.write(Image.new!(64, 64, color: [20, 120, 220]), :memory, suffix: ".png")

    upload = file_input(view, "#profile-card-form-#{me.id}", :profile_picture, [%{name: "me.png", content: png, type: "image/png"}])
    assert render_upload(upload, "me.png") =~ "me.png"
    view |> form("#profile-card-form-#{me.id}", %{"id" => me.id}) |> render_submit()

    assert %{picture_at: %DateTime{}} = Profiles.get(me.id)
    {:ok, back} = Image.from_binary(File.read!(Path.join(data_dir, PictureStore.relative_path(me.id))))
    assert {256, 256, _bands} = Image.shape(back)
    assert has_element?(view, "#{card(me.id)} [data-component='identity-tile'][data-mark='avatar']")

    view |> element("#edit-profile-picture-#{me.id}") |> render_click()
    view |> element("#remove-profile-picture-#{me.id}") |> render_click()
    view |> form("#profile-card-form-#{me.id}", %{"id" => me.id}) |> render_submit()
    assert %{picture_at: nil} = Profiles.get(me.id)
    refute File.exists?(Path.join(data_dir, PictureStore.relative_path(me.id)))
  end

  test "Remove profile arms, then removes", %{conn: conn} do
    ana = create_profile(name: "Ana")
    {:ok, view, _html} = live_async!(conn, @section)

    view |> element("#remove-profile-#{ana.id}") |> render_click()
    assert has_element?(view, "#remove-profile-#{ana.id}", "Click again to remove")
    assert Profiles.get(ana.id)

    view |> element("#remove-profile-#{ana.id}") |> render_click()
    assert Profiles.get(ana.id) == nil
    render_until(view, fn _html -> not has_element?(view, card(ana.id)) end)
  end
end
```

(`Image` is the `image` library already used by the social test; the PNG recipe is the one that test uses — copy its exact `Image.new!`/`Image.write` call if it differs.)

- [ ] **Step 2: Run it to see it fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_profiles_test.exs`
Expected: FAIL — the section does not exist (no cards).

- [ ] **Step 3: The section module**

`lib/media_centaur_web/live/settings_live/profiles_section.ex`:

```elixir
defmodule MediaCentaurWeb.SettingsLive.ProfilesSection do
  @moduledoc """
  The Profiles section of the Settings page (ADR-078, UIDR-053 rule 5):
  one card per profile — the tile, Picture (a Change picture button
  that opens the one picture field with its crop stage, one card at a
  time, saved by its own Save; Remove pending until that save), Name
  (saves on blur or Enter), Colour (`HueSwatches`, saves on the act) —
  with Remove profile as an arm gesture in the card's action slot,
  disabled on the last profile; and an Add card. `SettingsLive`
  delegates to `render/1` and hosts the handlers: `edit_profile_picture`,
  `stop_editing_picture`, `remove_profile_picture`,
  `cancel_profile_picture`, `save_profile_picture`,
  `validate_profile_card`, `set_profile_hue`, `rename_profile`,
  `remove_profile`, `add_profile`.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Profiles
  alias MediaCentaurWeb.Components.PictureField
  alias MediaCentaurWeb.Components.Social.HueSwatches
  alias MediaCentaurWeb.Components.Social.IdentityTile
  alias MediaCentaurWeb.Live.ArmGesture

  attr :profiles, :list, required: true, doc: "every `Profiles.Profile`, oldest first (`Live.ProfileAware`)"
  attr :uploads, :map, required: true, doc: "the LiveView's `@uploads`; `.profile_picture` is the field"
  attr :picture_editing, :string, default: nil, doc: "the id whose card shows the picture field"
  attr :picture_removed, :string, default: nil, doc: "the id whose Remove is pending until its save"
  attr :armed_gesture, :any, required: true, doc: "the page's `ArmGesture` slot"

  def render(assigns) do
    ~H"""
    <div id="settings-profiles" class="space-y-4">
      <.settings_card :for={profile <- @profiles} id={"profile-card-#{profile.id}"} title={profile.name} data-nav-grid>
        <:action>
          <.armed_button
            id={"remove-profile-#{profile.id}"}
            event="remove_profile"
            armed={ArmGesture.armed?(@armed_gesture, "remove_profile", profile.id)}
            armed_label="Click again to remove"
            phx-value-id={profile.id}
            disabled={length(@profiles) == 1}
          >
            Remove profile
          </.armed_button>
        </:action>
        <form
          id={"profile-card-form-#{profile.id}"}
          phx-change="validate_profile_card"
          phx-submit="save_profile_picture"
          class="space-y-3"
        >
          <input type="hidden" name="id" value={profile.id} />
          <div class="flex flex-wrap gap-x-8">
            <.settings_field
              label="Picture"
              description="Shown in the circle. One JPEG, PNG or WebP; drag the square to choose what shows."
              layout={:stacked}
              class="w-72 shrink-0"
            >
              <%= if @picture_editing == profile.id do %>
                <PictureField.picture_field
                  id={"profile-picture-#{profile.id}"}
                  upload={@uploads.profile_picture}
                  aspect={{1, 1}}
                  removable?={profile.picture_at != nil && @picture_removed != profile.id}
                  remove_event="remove_profile_picture"
                  cancel_event="cancel_profile_picture"
                  {IdentityTile.hue_style(profile.hue)}
                >
                  <:current>
                    <IdentityTile.identity_tile
                      name={profile.name}
                      picture_url={shown_picture(profile, @picture_removed)}
                      hue={profile.hue}
                      own?
                      size={48}
                    />
                  </:current>
                  <:preview><IdentityTile.crop_previews /></:preview>
                </PictureField.picture_field>
                <div class="flex gap-2 pt-2">
                  <.button type="submit" variant="secondary" size="sm" data-nav-item tabindex="0">
                    Save picture
                  </.button>
                  <.button type="button" variant="dismiss" size="sm" phx-click="stop_editing_picture" data-nav-item tabindex="0">
                    Cancel
                  </.button>
                </div>
              <% else %>
                <div class="flex items-center gap-3">
                  <IdentityTile.identity_tile
                    name={profile.name}
                    picture_url={Profiles.picture_url(profile)}
                    hue={profile.hue}
                    own?
                    size={48}
                  />
                  <.button
                    id={"edit-profile-picture-#{profile.id}"}
                    type="button"
                    variant="neutral"
                    size="sm"
                    phx-click="edit_profile_picture"
                    phx-value-id={profile.id}
                    data-nav-item
                    tabindex="0"
                  >
                    {if profile.picture_at, do: "Change picture", else: "Add picture"}
                  </.button>
                </div>
              <% end %>
            </.settings_field>
            <div class="min-w-0 grow basis-64">
              <.settings_field label="Name" layout={:stacked}>
                <.settings_input
                  id={"profile-name-#{profile.id}"}
                  name="name"
                  value={profile.name}
                  maxlength={DisplayName.max_length()}
                  autocomplete="off"
                  phx-blur="rename_profile"
                  phx-keydown="rename_profile"
                  phx-key="Enter"
                  phx-value-id={profile.id}
                  phx-debounce="blur"
                  class="max-w-64"
                />
              </.settings_field>
              <.settings_field label="Colour" description="The circle's colour." layout={:stacked}>
                <HueSwatches.hue_swatches
                  id={"profile-hues-#{profile.id}"}
                  selected={profile.hue}
                  event="set_profile_hue"
                  values={%{"id" => profile.id}}
                  aria-label="Colour"
                />
              </.settings_field>
            </div>
          </div>
        </form>
      </.settings_card>

      <.settings_card
        :if={length(@profiles) < Profiles.max_profiles()}
        id="add-profile"
        title="Add profile"
        description="Another person who watches here. They pick themselves on the Who's watching? screen."
      >
        <form id="settings-add-profile-form" phx-submit="add_profile" class="flex items-center gap-2">
          <.settings_input name="name" placeholder="Name" maxlength={DisplayName.max_length()} autocomplete="off" class="min-w-0 flex-1" />
          <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">Add profile</.button>
        </form>
      </.settings_card>
    </div>
    """
  end

  # The tile shows the stored picture, or the letter once Remove is pending.
  defp shown_picture(profile, removed_id) do
    if removed_id == profile.id, do: nil, else: Profiles.picture_url(profile)
  end
end
```

- [ ] **Step 4: Wire `SettingsLive`**

In `lib/media_centaur_web/live/settings_live.ex`:

1. Add to `@sections` after the `preferences` entry:

```elixir
    %{
      id: "profiles",
      label: "Profiles",
      group: :general,
      description: "Who watches on this install. Each profile is picked on the Who's watching? screen."
    },
```

2. In `mount/3`, after the avatar `allow_upload`: `socket = allow_upload(socket, :profile_picture, PictureField.upload_options())`, and add `|> assign(picture_editing: nil, picture_removed: nil)` to the assign chain.

3. Aliases: `alias MediaCentaur.Profiles`, `alias MediaCentaur.Profiles.PictureStore`, `alias MediaCentaurWeb.SettingsLive.ProfilesSection`, `alias MediaCentaurWeb.ProfileWords` (if not added in Task 7).

4. The section dispatch, beside `section_content(%{active_section: "social"})`:

```elixir
  defp section_content(%{active_section: "profiles"} = assigns) do
    ~H"""
    <ProfilesSection.render
      profiles={@profiles}
      uploads={@uploads}
      picture_editing={@picture_editing}
      picture_removed={@picture_removed}
      armed_gesture={@armed_gesture}
    />
    """
  end
```

5. The handlers, in a `# --- Profiles ---` block:

```elixir
  def handle_event("add_profile", %{"name" => name}, socket) do
    case Profiles.add(name) do
      {:ok, profile} -> {:noreply, put_flash(socket, :info, "Added #{profile.name}")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, ProfileWords.error(reason))}
    end
  end

  def handle_event("rename_profile", %{"id" => id, "value" => name}, socket) do
    with %Profiles.Profile{} = profile <- Profiles.get(id),
         {:ok, _renamed} <- Profiles.rename(profile, name) do
      {:noreply, socket}
    else
      nil -> {:noreply, socket}
      {:error, reason} -> {:noreply, put_flash(socket, :error, ProfileWords.error(reason))}
    end
  end

  # The hue slider is a field of the card's form; a drag lands here as `hue`.
  def handle_event("validate_profile_card", %{"_target" => ["hue"], "hue" => hue, "id" => id}, socket),
    do: {:noreply, set_viewer_hue(socket, id, hue)}

  # The upload's change event: LiveView needs it bound to track the entry.
  def handle_event("validate_profile_card", _params, socket), do: {:noreply, socket}

  def handle_event("set_profile_hue", %{"hue" => hue, "id" => id}, socket),
    do: {:noreply, set_viewer_hue(socket, id, hue)}

  def handle_event("edit_profile_picture", %{"id" => id}, socket),
    do: {:noreply, assign(socket, picture_editing: id, picture_removed: nil)}

  def handle_event("stop_editing_picture", _params, socket),
    do: {:noreply, socket |> drop_profile_picture_entries() |> assign(picture_editing: nil, picture_removed: nil)}

  def handle_event("remove_profile_picture", _params, socket),
    do: {:noreply, assign(socket, picture_removed: socket.assigns.picture_editing)}

  def handle_event("cancel_profile_picture", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :profile_picture, ref)}

  def handle_event("save_profile_picture", %{"id" => id} = params, socket) do
    {socket, change} =
      PictureField.consume_change(
        socket,
        :profile_picture,
        {:webp, PictureStore.master_size(), PictureStore.max_bytes()},
        PictureField.crop_from_params(params),
        socket.assigns.picture_removed == id
      )

    with %Profiles.Profile{} = profile <- Profiles.get(id),
         {:ok, change} <- change,
         {:ok, _updated} <- apply_profile_picture(profile, change) do
      {:noreply,
       socket
       |> assign(picture_editing: nil, picture_removed: nil)
       |> put_flash(:info, "Picture saved")}
    else
      nil -> {:noreply, assign(socket, picture_editing: nil, picture_removed: nil)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, ProfileWords.error(reason))}
    end
  end

  def handle_event("remove_profile", %{"id" => id}, socket) do
    case ArmGesture.press(socket, "remove_profile", id) do
      {:armed, socket} ->
        {:noreply, socket}

      {:fire, socket} ->
        with %Profiles.Profile{} = profile <- Profiles.get(id),
             :ok <- Profiles.remove(profile) do
          {:noreply, put_flash(socket, :info, "Profile removed")}
        else
          nil -> {:noreply, socket}
          {:error, reason} -> {:noreply, put_flash(socket, :error, ProfileWords.error(reason))}
        end
    end
  end
```

and the private helpers beside `assign_hue/2`:

```elixir
  # A viewer profile's hue saves on the act (UIDR-041 §2); an empty slider
  # value or a malformed one changes nothing.
  defp set_viewer_hue(socket, id, value) do
    with %Profiles.Profile{} = profile <- Profiles.get(id),
         {:ok, hue} when is_integer(hue) <- Hue.parse(value),
         {:ok, _updated} <- Profiles.set_hue(profile, hue) do
      socket
    else
      {:error, reason} -> put_flash(socket, :error, ProfileWords.error(reason))
      _nil_or_empty -> socket
    end
  end

  defp apply_profile_picture(_profile, :keep), do: {:ok, :kept}
  defp apply_profile_picture(profile, change), do: Profiles.set_picture(profile, change)

  # Cancel on the card drops whatever was chosen, so the next card to open
  # the field starts empty.
  defp drop_profile_picture_entries(socket) do
    Enum.reduce(socket.assigns.uploads.profile_picture.entries, socket, fn entry, socket ->
      cancel_upload(socket, :profile_picture, entry.ref)
    end)
  end
```

6. In `test/media_centaur_web/page_smoke_test.exs` add `profiles` to the `~w(…)` section list after `preferences`.

- [ ] **Step 5: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_profiles_test.exs test/media_centaur_web/live/settings_live_social_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: PASS.

- [ ] **Step 6: Look at it**

With the dev server running: `~/scripts/agents/page-shot --url "http://127.0.0.1:2160/settings?section=profiles" --viewport 1920x1080 --wait-ms 3000` and Read the PNG. The cards follow the Social section's two-column shape; the picture field opens on Change picture.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: Settings → Profiles — add, rename, picture, colour, remove"
```

---

### Task 13: Docs and the wiki

**Files:**
- Modify: `docs/GLOSSARY.md`, `.claude/skills/user-interface/SKILL.md` (component inventory row), `docs/superpowers/specs/2026-10-06-viewer-profiles-design.md` (two amendments), `campaigns/viewer-profiles.md`
- Modify: wiki `Settings-Reference.md`

- [ ] **Step 1: Glossary**

In `docs/GLOSSARY.md`, in the social section's **Profile** row (line ~202) rename the term to **Social profile** and open it with "What one key publishes about itself (`Social.Profile`, table `social_profiles`) — in user-facing words always the two words, since a *profile* alone is a viewer profile:". Add a new section before "## Apps":

```markdown
## Profiles

The vocabulary of the viewer-profiles campaign (ADR-078, UIDR-053).

| Term | Meaning |
|---|---|
| **Profile** (viewer profile) | One person who watches on this install: `Profiles.Profile`, table `profiles` — name, hue, `picture_at` — picked on the screen and edited under Settings → Profiles. The plain word; the social kind is always *social profile*. Phase 2 hangs the watching rows off it. |
| **Active profile** | The profile a browser session is using: the `"profile_id"` key of the signed session cookie, written by `ProfileController.activate/2`, read by `Live.ProfileAware` into `:profile`. With one profile the cookie is never consulted. |
| **Picker** | `/profiles`, "Who's watching?": a tile per profile posting to the activate route, and an inline Add under the cap of eight. A session with no active profile is sent there with `return_to`. |
| **Switcher** | The active profile's tile in the sidebar (`#sidebar-profile`), a link to the picker; present only with more than one profile. |
| **Picture store** | `Profiles.PictureStore`: one 256×256 WebP per profile at `{data_dir}/images/profiles/<id>.webp`, over `ImageFiles`' `write_file/2`, `remove_file/1`, `url_if_present/2` — the primitives `Social.AvatarStore` shares. |
```

- [ ] **Step 2: The user-interface skill's inventory row**

In `.claude/skills/user-interface/SKILL.md` replace the `identity_tile/1` row with:

```markdown
| `identity_tile/1`, `crop_previews/1` | `social/identity_tile.ex` | The app's one drawing of a person from three facts — name, picture, hue — filled (`own?`) or tinted, at 32, 40, 48 or 96 (UIDR-047, UIDR-053); `person_attrs/1` turns a `Social.Person` into them; the crop stage's two preview frames | ✅ |
```

- [ ] **Step 3: Spec amendments**

In `docs/superpowers/specs/2026-10-06-viewer-profiles-design.md` add under "## Design" a dated note:

```markdown
**Amendments 2026-10-06 (planning).** (1) The owner profile is named
"Me" by the migration and carries no hue or picture; nothing reads the
social profile, since a migration cannot derive the identity's key and
a boot-time copy would need a heuristic for "never edited". Rename it
in Settings. (2) The picker's Add is an inline form on the picker
itself, not a link to Settings: with no active profile, Settings would
redirect back to the picker. (3) The cursor starts on the first tile;
the "last used" start is dropped. (4) The social card's ids and events
take a `social_` prefix with the relabel (`#social-profile-form`,
`save_social_profile`, …). (5) Five convergences from the unify pass:
`ImageFiles` picture primitives, `PictureField.consume_change/5`,
`MediaCentaur.DisplayName`, `MediaCentaurWeb.ProfileWords`,
`IdentityTile.crop_previews/1`. (6) Remove profile's line "Their
watching history goes with it." waits for phase 2, when it becomes true.
```

- [ ] **Step 4: Wiki Settings reference**

In `../media-centaur.wiki/Settings-Reference.md` add after the `### Preferences` section:

```markdown
### Profiles

Who watches on this install. One card per profile:

- **Picture** — **Add picture** (or **Change picture**) opens the picture field: choose a JPEG, PNG or WebP, drag the square to choose what shows, **Save picture**. **Remove** clears it on the next save.
- **Name** — up to 50 characters; saves when you leave the field or press Enter.
- **Colour** — the circle's colour, from the swatches or the ring.
- **Remove profile** — click, then click again to confirm. The last profile can't be removed.

**Add profile** adds another person. With more than one profile the app asks **Who's watching?** when it opens, and the sidebar shows the active profile; press it to switch. In this release every profile still shares one watch history; the next release gives each its own.
```

Commit the wiki with `git commit -am "wiki: Settings → Profiles"` (no push).

- [ ] **Step 5: Campaign file**

In `campaigns/viewer-profiles.md` set `last_updated` to today, Status to "Phase 1 built on branch `viewer-profiles` (worktree `../media-centaur-app-viewer-profiles`); owner's visual check and merge next; phase 2 plan after.", and append to Decisions made the five convergences with the plan's path.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs: profiles glossary, inventory row, spec amendments, campaign status"
```

---

### Task 14: Precommit and the whole-suite run

- [ ] **Step 1: Precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: format clean, credo clean (MC0009 satisfied by the two stories; if it names a missing story path for `crop_previews`, create it at the path it names), boundaries clean, 0 warnings, all tests pass.

Likely findings and their fixes:
- `Boundary` reports `MediaCentaurWeb` calling `MediaCentaur.Profiles` → the deps entry from Task 9 step 3 is missing.
- A `storybook_render_test` failure on `identity_tile` → a variation still passes `person:`.
- A page test failing with "missing required attribute profile" → a `<Layouts.app` call site was missed (Task 9 step 5).

- [ ] **Step 2: Context map**

Run: `~/scripts/agents/agent-mix context_map --diff`
Expected: the `added` section lists only crossings into `MediaCentaur.Profiles.Profile` from the web layer (`ProfileAware`, `Layouts`, `ProfilesSection`, `ProfilesLive`). Add a verdict for each in `docs/context-map/verdicts.json` (`allowed`: "the web layer reads the profile row it was handed by the hook"), then `agent-mix context_map` to regenerate the committed map.

- [ ] **Step 3: Final commit and hand-off**

```bash
git add -A
git commit -m "chore: context-map verdicts for the Profiles context"
git log --oneline main..HEAD
```

Report the branch and worktree path to the owner. Do not merge; do not push.
