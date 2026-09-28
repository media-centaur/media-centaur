# Profiles, phase 5a: the hue and the name field. Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person's circle takes a hue they chose; the reader can choose another for a friend; the Settings name field stops filling the card.

**Architecture:** A colour is a **hue**, an angle 0–359 on one oklch ring whose lightness and chroma the theme fixes in CSS (`--person-l`, `--person-c`; UIDR-048). `Social.Hue` owns what a hue is (the type, `valid?/1`, `parse/1`, the eight-entry `palette/0`, `random/0`). The profile carries it as the optional integer field `hue` (ADR-073 amended); `profiles.hue` and `friends.hue_override` are two nullable columns; `Person` gains `published_hue` and `hue_override`, resolved by `Person.hue/1` at the one seam that resolves the name. The identity tile's colours move from Tailwind utilities to four CSS classes over `--hue`, so one recipe draws every hue and the default. One function component, `Discovery.HueSwatches`, is the swatch row and the ring slider on both Settings and the card foot. The release also drops `friends.nickname` (owed since v1.42.0) and renames the `:start_activities_sync` key to `:start_relay_sync`.

**Tech Stack:** Elixir 1.20 / Phoenix LiveView 1.2, Ecto + `ecto_sqlite3`, Tailwind v4 + daisyUI, Phoenix Storybook, ExUnit + LazyHTML.

**Design:** `docs/superpowers/specs/2026-09-27-profiles-design.md` § Phase 5 (the hue, the name field; not the crop, which is phase 5b). UIDR-048; ADR-073 and UIDR-047's 2026-09-28 amendments. Campaign `campaigns/profiles.md`.

---

## Unify pass (2026-09-28)

**Core idea.** A person's appearance is one published record — name, avatar, hue — overlaid by the reader's choices for a friend — name override, show avatar, hue override. The hue is the third field of the same structure on both sides and is resolved where the other two are (`Social.person_for/2`, `own_person_for/2`).

**Greenfield shape.** A value module for the hue; the wire content as one map in both directions; the tile drawing whatever hue it is handed through one CSS custom property; one swatch component with one payload shape; the reader's override on the roster row beside the name override.

**Diff against the code, each incoherence decided:**

1. `Profile.Translation.to_event/4` took the name and the avatar as positional arguments; a fifth for the hue was the bolt-on. **Fixed now**: `to_event/3` takes a fields map (`name`, `avatar`, `hue`), the shape `from_event/1` already returns. Twelve call sites, listed in Task 1.
2. `Social.save_profile/2` becomes `/3` with the hue as the third argument; three arguments is the ceiling and the form always has all three. **Kept positional.** Callers listed in Task 3.
3. The identity tile's colours were Tailwind utilities naming `primary`; a hue cannot be a utility. **Fixed now**: four CSS classes over `--hue` with `250` as the fallback, so a person with no hue is drawn by the same recipe as one with. The avatar rings were `ring-inset`, which an `<img>` child paints over; they become outset rings, the same 1 px / 2 px weights.
4. A ninth "Custom" swatch that reveals the slider needs state a function component has not. **Fixed in the spec**: the slider is always under the swatches and is the custom choice; its `name="hue"` rides the host's form's `phx-change`, so a click and a drag reach one handler with one payload.
5. The `:start_activities_sync` key "predates the loop's move out of Activities and keeps its name" until the `nickname` drop. **Fixed now**, with the drop: `:start_relay_sync`.
6. Every `Person` field added must reach `test/support/discovery_rows.ex` and the story fixture builders. Both new fields default to nil in the struct, so the builders are unchanged; the tile story gains the hue variations (Task 4).

**Coherence cost.** Item 1 touches twelve call sites for no user-visible change; item 3 rewrites a component's classes that already work. Both are one task each and leave one representation where there would have been two.

## Read before starting

- **Never run `mix` directly.** Every command is `~/scripts/agents/agent-mix …`. The dev daily driver compiles into this checkout's `_build/dev`.
- **Test first**, red then green, per task. The suite stays green at every commit.
- Work on `main`, commit per task, push nothing. No relay change: the hue is a content field of kind 12160.
- **Commit messages**: conventional, plain prose, the harness's attribution trailer, never `Co-Authored-By`.
- **Copy**: user copy says *colour*; code and the wire say `hue`. Swatch names are the palette's (Rose, Orange, Amber, Green, Teal, Blue, Violet, Magenta); the slider's accessible name is "Any colour"; the foot's first swatch is "Theirs".
- **Storybook**: MC0009 — `HueSwatches` needs a story in the same commit; the tile and person card stories gain variations in theirs.
- **Zero warnings.** Every function added gains a caller in this phase.
- **Migrations** run on the agent build root's database; `~/scripts/agents/agent-mix ecto.migrate` before the tests that need the columns.

## What this phase does not do, on purpose

- No cropper, no preview (phase 5b).
- No hue derived from a key; no hue for the own tile that the person did not save.
- No hue on the pennant, the detail panel's attributed words, or anywhere but the tile.
- No global palette setting.

## File structure

Created:

- `lib/media_centaur/social/hue.ex` — the value module.
- `lib/media_centaur_web/components/discovery/hue_swatches.ex`, `storybook/discovery/hue_swatches.story.exs`, `test/media_centaur_web/components/discovery/hue_swatches_test.exs`.
- `test/media_centaur/social/hue_test.exs`.
- `priv/repo/migrations/20260928130000_profiles_carry_a_hue.exs`, `…131000_friends_hue_override.exs`, `…132000_friends_drop_nickname.exs`.

Modified: `lib/media_centaur/social.ex`, `social/profile.ex`, `social/profile/translation.ex`, `social/friend.ex`, `social/person.ex`; `lib/media_centaur/application.ex`, `relay_sync.ex`, `config/test.exs`; `assets/css/app.css`; `lib/media_centaur_web/components/discovery/identity_tile.ex`, `person_card.ex`; `lib/media_centaur_web/live/settings_live.ex`, `settings_live/social_section.ex`, `discovery_live.ex`; stories `identity_tile`, `person_card`; tests per task; `docs/social-protocol.md`, `docs/social.md`, `docs/GLOSSARY.md`, wiki `Social.md`, `Settings-Reference.md`, `campaigns/profiles.md`, `campaigns/README.md`.

---

### Task 1: `Social.Hue`; the hue on the wire and in the row

**Files:**
- Create: `lib/media_centaur/social/hue.ex`, `test/media_centaur/social/hue_test.exs`, `priv/repo/migrations/20260928130000_profiles_carry_a_hue.exs`
- Modify: `lib/media_centaur/social/profile/translation.ex`, `lib/media_centaur/social/profile.ex`, `lib/media_centaur/social.ex:1-20` (exports) and `:258`
- Test: `test/media_centaur/social/profile_translation_test.exs`, `test/media_centaur/social/profile_test.exs`

- [ ] **Step 1: The Hue tests**

Create `test/media_centaur/social/hue_test.exs`:

```elixir
defmodule MediaCentaur.Social.HueTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Social.Hue

  test "a hue is an integer angle 0–359" do
    assert Hue.valid?(0)
    assert Hue.valid?(359)
    refute Hue.valid?(360)
    refute Hue.valid?(-1)
    refute Hue.valid?(250.0)
    refute Hue.valid?("250")
    refute Hue.valid?(nil)
  end

  test "the palette is eight named hues, Blue 250 among them; random picks one" do
    palette = Hue.palette()
    assert length(palette) == 8
    assert {"Blue", 250} in palette
    assert Enum.all?(palette, fn {name, hue} -> is_binary(name) and Hue.valid?(hue) end)
    assert Hue.random() in Enum.map(palette, &elem(&1, 1))
  end

  test "parse/1 reads a form value: an angle, empty for none, anything else refused" do
    assert Hue.parse("195") == {:ok, 195}
    assert Hue.parse("") == {:ok, nil}
    assert Hue.parse(nil) == {:ok, nil}
    assert Hue.parse("360") == :error
    assert Hue.parse("12.5") == :error
    assert Hue.parse("teal") == :error
  end
end
```

- [ ] **Step 2: Run, expect the module missing**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/hue_test.exs`
Expected: FAIL, `Hue.valid?/1 is undefined`.

- [ ] **Step 3: `Social.Hue`**

Create `lib/media_centaur/social/hue.ex`:

```elixir
defmodule MediaCentaur.Social.Hue do
  @moduledoc """
  A person's colour is a hue (UIDR-048): an integer angle 0–359 on one
  oklch ring whose lightness and chroma the theme fixes (`--person-l`,
  `--person-c` in `app.css`), so nothing published can be dark, pastel
  or grey and a letter's contrast never depends on the choice. On the
  wire it is the profile's optional `hue` field (ADR-073); in the row,
  `profiles.hue` and the reader's `friends.hue_override`. User copy says
  *colour*; code and the wire say hue.

  The palette is the eight named angles the swatch row offers; any
  other angle comes from the slider. `random/0` seeds a new profile's
  form. A person with no hue is drawn at 250, the primary's angle, by
  CSS alone (`var(--hue, 250)`); no function here supplies a default.
  """

  @type t :: 0..359

  @palette [
    {"Rose", 12},
    {"Orange", 45},
    {"Amber", 80},
    {"Green", 150},
    {"Teal", 195},
    {"Blue", 250},
    {"Violet", 290},
    {"Magenta", 335}
  ]

  @doc "Whether a term is a hue: an integer 0–359. A float is not."
  @spec valid?(term()) :: boolean()
  def valid?(hue), do: is_integer(hue) and hue >= 0 and hue <= 359

  @doc "The eight named hues the swatch row offers, in ring order."
  @spec palette() :: [{String.t(), t()}]
  def palette, do: @palette

  @doc "A palette hue at random: the seed for a profile that has none yet."
  @spec random() :: t()
  def random, do: @palette |> Enum.random() |> elem(1)

  @doc "A form value as a hue: the angle, nil for empty or absent, `:error` for anything else."
  @spec parse(String.t() | nil) :: {:ok, t() | nil} | :error
  def parse(nil), do: {:ok, nil}
  def parse(""), do: {:ok, nil}

  def parse(value) when is_binary(value) do
    case Integer.parse(value) do
      {hue, ""} -> if valid?(hue), do: {:ok, hue}, else: :error
      _other -> :error
    end
  end
end
```

Add `Hue` to the `exports:` list in `lib/media_centaur/social.ex` (alphabetically, after `Friend`).

- [ ] **Step 4: Run, expect green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/hue_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: The translation tests — the fields map and the hue**

In `test/media_centaur/social/profile_translation_test.exs`, every `Translation.to_event(name, avatar, pubkey, at)` becomes `Translation.to_event(%{name: name, avatar: avatar}, pubkey, at)` (lines 30, 37, 78, 81; drop a nil field or keep it, both are left off the wire). Then add, after the `to_event/4 leaves an absent name` test:

```elixir
  test "to_event/3 carries the hue as an integer; an absent one is left off the wire" do
    assert Jason.decode!(Translation.to_event(%{name: "Sample Name", hue: 195}, @pubkey, 1).content) ==
             %{"v" => 1, "name" => "Sample Name", "hue" => 195}

    refute Map.has_key?(Jason.decode!(Translation.to_event(%{name: "x"}, @pubkey, 1).content), "hue")
  end

  test "from_event/1 reads the hue; absent or null is none; anything else drops the profile" do
    assert {:ok, %{hue: 195}} = Translation.from_event(signed(~s({"v":1,"hue":195})))
    assert {:ok, %{hue: 0}} = Translation.from_event(signed(~s({"v":1,"hue":0})))
    assert {:ok, %{hue: nil}} = Translation.from_event(signed(~s({"v":1})))
    assert {:ok, %{hue: nil}} = Translation.from_event(signed(~s({"v":1,"hue":null})))

    for bad <- [~s("195"), "195.0", "360", "-1", "true", "[195]"] do
      assert {:error, :bad_content} = Translation.from_event(signed(~s({"v":1,"hue":#{bad}}))),
             "a hue of #{bad} must drop the profile"
    end
  end
```

- [ ] **Step 6: Run, expect the arity and the hue to fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/profile_translation_test.exs`
Expected: FAIL — `to_event/3` undefined, then the hue assertions.

- [ ] **Step 7: The translation**

In `lib/media_centaur/social/profile/translation.ex`:

Moduledoc: after the avatar paragraph add:

```
  The hue is the optional integer field `"hue"`, 0–359 (`Social.Hue`),
  absent or null when the key gives none; a float, a string or an
  integer out of range drops the whole profile.
```

Replace `alias MediaCentaur.Nostr.Event` with:

```elixir
  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Social.Hue
```

Replace the `@type avatar` and `@type attrs` block with:

```elixir
  @type avatar :: %{type: String.t(), bytes: binary()}
  @typedoc "The content a sender gives, one map: a nil or absent field is left off the wire."
  @type fields :: %{
          optional(:name) => String.t() | nil,
          optional(:avatar) => avatar() | nil,
          optional(:hue) => Hue.t() | nil
        }
  @type attrs :: %{
          pubkey: String.t(),
          name: String.t() | nil,
          avatar_type: String.t() | nil,
          avatar_bytes: binary() | nil,
          hue: Hue.t() | nil,
          raw_event: map(),
          created_at: non_neg_integer()
        }
```

Replace `to_event/4` with:

```elixir
  @doc "An unsigned profile event for `pubkey` at `created_at` carrying `fields`; a nil or absent field is left off the wire."
  @spec to_event(fields(), String.t(), non_neg_integer()) :: Event.t()
  def to_event(fields, pubkey, created_at) when is_map(fields) do
    content =
      %{"v" => @content_version}
      |> put_present("name", fields[:name])
      |> put_present("avatar", encode_avatar(fields[:avatar]))
      |> put_present("hue", fields[:hue])

    Event.new(%{
      pubkey: pubkey,
      created_at: created_at,
      kind: @kind,
      tags: [],
      content: Jason.encode!(content)
    })
  end
```

and add beside `put_present/3`:

```elixir
  defp encode_avatar(nil), do: nil
  defp encode_avatar(avatar), do: %{"type" => avatar.type, "data" => Base.encode64(avatar.bytes)}
```

In `from_event/1`, extend the `with` and the map:

```elixir
    with {:ok, content} <- decode(event.content),
         :ok <- check_version(content),
         {:ok, name} <- read_name(content),
         {:ok, avatar} <- read_avatar(content),
         {:ok, hue} <- read_hue(content) do
      {:ok,
       %{
         pubkey: event.pubkey,
         name: name,
         avatar_type: avatar && avatar.type,
         avatar_bytes: avatar && avatar.bytes,
         hue: hue,
         raw_event: Event.to_map(event),
         created_at: event.created_at
       }}
    end
```

and after `read_avatar/1`'s clauses:

```elixir
  # An integer angle on the ring, or none. Jason gives `195.0` as a float,
  # which is not an integer and drops the profile like a string would.
  defp read_hue(%{"hue" => hue}) when is_integer(hue),
    do: if(Hue.valid?(hue), do: {:ok, hue}, else: {:error, :bad_content})

  defp read_hue(%{"hue" => nil}), do: {:ok, nil}
  defp read_hue(%{"hue" => _not_an_angle}), do: {:error, :bad_content}
  defp read_hue(_absent), do: {:ok, nil}
```

In `lib/media_centaur/social.ex:258`, `name |> ProfileTranslation.to_event(avatar, me, created_at)` becomes `ProfileTranslation.to_event(%{name: name, avatar: avatar}, me, created_at)` for now (Task 3 adds the hue).

Rewrite the other callers to the fields map, same shape each: `test/media_centaur/social/profile_test.exs:23, 128, 145, 155, 183`; `test/media_centaur/social/person_test.exs:52`; `test/media_centaur/relay_sync_test.exs:290`; `test/media_centaur_web/live/discovery_live_test.exs:194`.

- [ ] **Step 8: The row: `profiles.hue`**

Create `priv/repo/migrations/20260928130000_profiles_carry_a_hue.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.ProfilesCarryAHue do
  @moduledoc "A profile's hue, an integer 0–359 (UIDR-048), nil when the key published none. A plain add the outgoing release never reads."
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :hue, :integer
    end
  end
end
```

In `lib/media_centaur/social/profile.ex`: add `field :hue, :integer` after `avatar_type`; cast it: `cast(attrs, [:pubkey, :name, :avatar_type, :hue, :raw_event, :created_at])`; add `|> validate_number(:hue, greater_than_or_equal_to: 0, less_than_or_equal_to: 359)` after `validate_required`. Moduledoc: "its name, its avatar's type and its hue".

- [ ] **Step 9: A stored hue round-trips through ingest**

In `test/media_centaur/social/profile_test.exs`, in `describe "ingest_profile/1"`, add:

```elixir
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
```

(Use the file's existing friend secret/pubkey module attributes; read its head for their names.)

- [ ] **Step 10: Migrate, run, expect green**

Run: `~/scripts/agents/agent-mix ecto.migrate && ~/scripts/agents/agent-mix test test/media_centaur/social/ test/media_centaur/relay_sync_test.exs`
Expected: 0 failures.

- [ ] **Step 11: Commit**

```bash
git add lib/media_centaur/social/hue.ex lib/media_centaur/social/profile/translation.ex lib/media_centaur/social/profile.ex lib/media_centaur/social.ex priv/repo/migrations/20260928130000_profiles_carry_a_hue.exs test/media_centaur/social/ test/media_centaur/relay_sync_test.exs test/media_centaur_web/live/discovery_live_test.exs
git commit -m "feat: a profile carries a hue on the wire and in the row; Social.Hue owns the ring; to_event takes the content as one map"
```

---

### Task 2: The reader's override; `nickname` dropped; the sync key renamed

**Files:**
- Create: `priv/repo/migrations/20260928131000_friends_hue_override.exs`, `priv/repo/migrations/20260928132000_friends_drop_nickname.exs`
- Modify: `lib/media_centaur/social/friend.ex`, `lib/media_centaur/social.ex` (after `set_show_avatar/2`), `lib/media_centaur/application.ex:290-297`, `lib/media_centaur/relay_sync.ex:50`, `config/test.exs:82`, `docs/social.md:504`
- Test: `test/media_centaur/social/friend_test.exs`

- [ ] **Step 1: The test**

In `test/media_centaur/social/friend_test.exs`, after `describe "set_show_avatar/2"`:

```elixir
  describe "set_hue_override/2" do
    test "sets the reader's hue, clears it with nil, broadcasts once per change; a bad hue or key is refused" do
      {:ok, %Friend{hue_override: nil}} = Social.add_friend(@pubkey, "One")
      Social.subscribe()

      assert {:ok, %Friend{hue_override: 195}} = Social.set_hue_override(@pubkey, 195)
      assert_receive {:friend_changed, %FriendChanged{pubkey: @pubkey}}, 500
      assert {:ok, %Friend{hue_override: 195}} = Social.set_hue_override(@pubkey, 195)
      refute_receive {:friend_changed, _event}, 100

      assert {:ok, %Friend{hue_override: nil}} = Social.set_hue_override(@pubkey, nil)
      assert_receive {:friend_changed, %FriendChanged{pubkey: @pubkey}}, 500

      assert {:error, :invalid_hue} = Social.set_hue_override(@pubkey, 360)
      assert {:error, :not_a_friend} = Social.set_hue_override(String.duplicate("a", 64), 12)
    end
  end
```

- [ ] **Step 2: Run, expect undefined**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/friend_test.exs`
Expected: FAIL, `set_hue_override/2` undefined.

- [ ] **Step 3: The column, the schema, the function**

Create `priv/repo/migrations/20260928131000_friends_hue_override.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.FriendsHueOverride do
  @moduledoc "The reader's hue for a friend, an integer 0–359 masking the published one (UIDR-048); nil is none. A plain add."
  use Ecto.Migration

  def change do
    alter table(:friends) do
      add :hue_override, :integer
    end
  end
end
```

Create `priv/repo/migrations/20260928132000_friends_drop_nickname.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.FriendsDropNickname do
  @moduledoc """
  The second half of the paired migration `FriendsNameOverrideIsOptional`
  (v1.42.0): `nickname` was kept nullable for the release that still read
  it; this release, the first after it, drops the column. Down re-adds it
  empty.
  """
  use Ecto.Migration

  def change do
    alter table(:friends) do
      remove :nickname, :text
    end
  end
end
```

In `lib/media_centaur/social/friend.ex`: add `field :hue_override, :integer` after `show_avatar`; cast it; add `|> validate_number(:hue_override, greater_than_or_equal_to: 0, less_than_or_equal_to: 359)`; moduledoc: replace the last paragraph ("The table still carries a nullable `nickname` column…") with "`hue_override` is the reader's hue for the friend (UIDR-048), masking the published one; nil is none."

In `lib/media_centaur/social.ex`, after `set_show_avatar/2`:

```elixir
  @doc """
  Sets the reader's hue for a friend (UIDR-048), masking the one the
  friend published; nil clears it and the published hue, else the
  default, stands in. Broadcasts `FriendChanged` when it changed.
  """
  @spec set_hue_override(String.t(), Hue.t() | nil) ::
          {:ok, Friend.t()} | {:error, :not_a_friend | :invalid_hue}
  def set_hue_override(pubkey, hue) when is_binary(pubkey) do
    with :ok <- valid_hue(hue),
         {:ok, friend} <- known_friend(pubkey) do
      apply_change(friend, %{hue_override: hue})
    end
  end
```

and among the private helpers:

```elixir
  defp valid_hue(nil), do: :ok
  defp valid_hue(hue), do: if(Hue.valid?(hue), do: :ok, else: {:error, :invalid_hue})
```

Add `alias MediaCentaur.Social.Hue` in alphabetical order. Update the `apply_change/2` comment: "the name is optional, the switch is a boolean by guard, the hue is checked by `valid_hue/1`".

- [ ] **Step 4: The sync key**

`config/test.exs:82`: `config :media_centaur, :start_relay_sync, false`. `lib/media_centaur/application.ex:290-297`: the key becomes `:start_relay_sync` and the comment's last sentence ("The key predates the loop's move… keeps its name.") is deleted. `lib/media_centaur/relay_sync.ex:50`: `(`:start_relay_sync`)`. `docs/social.md:504`: the key's row renamed.

- [ ] **Step 5: Migrate, run, expect green**

Run: `~/scripts/agents/agent-mix ecto.migrate && ~/scripts/agents/agent-mix test test/media_centaur/social/ test/media_centaur/relay_sync_test.exs`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations/20260928131000_friends_hue_override.exs priv/repo/migrations/20260928132000_friends_drop_nickname.exs lib/media_centaur/social/friend.ex lib/media_centaur/social.ex lib/media_centaur/application.ex lib/media_centaur/relay_sync.ex config/test.exs docs/social.md test/media_centaur/social/friend_test.exs
git commit -m "feat: the reader's hue for a friend; friends.nickname dropped as owed; the sync gate is :start_relay_sync"
```

---

### Task 3: The Person resolves the hue; `save_profile/3` publishes it

**Files:**
- Modify: `lib/media_centaur/social/person.ex`, `lib/media_centaur/social.ex` (`people/0`, `save_profile/2`, `own_person_for/2`, `person_for/2`), `lib/media_centaur_web/live/settings_live.ex:953` (a `nil` for now; Task 6 passes the real hue)
- Test: `test/media_centaur/social/person_test.exs`, `test/media_centaur/social/profile_test.exs`

- [ ] **Step 1: The tests**

In `test/media_centaur/social/person_test.exs`, inside `describe "people/0"`:

```elixir
    test "the hue: the reader's override, else the published one, else nil; the own Person has no override" do
      {:ok, _friend} = Social.add_friend(@signer, "Nick")
      assert %Person{published_hue: nil, hue_override: nil} = person = Social.people()[@signer]
      assert Person.hue(person) == nil

      {:ok, _profile} =
        Social.ingest_profile(
          Event.sign(Translation.to_event(%{name: "One", hue: 195}, @signer, 1_700_000_000), @signer_secret)
        )

      assert %Person{published_hue: 195, hue_override: nil} = person = Social.people()[@signer]
      assert Person.hue(person) == 195

      {:ok, _friend} = Social.set_hue_override(@signer, 12)
      assert %Person{published_hue: 195, hue_override: 12} = person = Social.people()[@signer]
      assert Person.hue(person) == 12

      {:ok, _profile} = Social.save_profile("Me", :keep, 290)
      me = Social.own_person()
      assert %Person{own?: true, published_hue: 290, hue_override: nil} = me
      assert Person.hue(me) == 290
    end
```

(`@signer_secret` is whatever the file names the signer's secret; read its head.)

In `test/media_centaur/social/profile_test.exs`, every `Social.save_profile(a, b)` becomes `Social.save_profile(a, b, nil)` (lines 30, 31, 35, 43, 86, 95, 106, 113, 117, 164, 170, 173, 193, 205), likewise `test/media_centaur/relay_sync_test.exs:80, 305, 316`, `test/media_centaur/social/person_test.exs:76`, `test/media_centaur_web/live/settings_live_social_test.exs:168, 217`. Then add to `describe "save_profile/2"` (rename it `"save_profile/3"`):

```elixir
    test "publishes the hue with the name; an out-of-range hue is refused before minting" do
      assert {:error, :invalid_hue} = Social.save_profile("Me", :keep, 360)
      refute Identity.present?()

      assert {:ok, %Profile{hue: 195, raw_event: raw}} = Social.save_profile("Me", :keep, 195)
      assert Jason.decode!(raw["content"])["hue"] == 195
      assert {:ok, %Profile{hue: nil}} = Social.save_profile("Me", :keep, nil)
    end
```

- [ ] **Step 2: Run, expect failures**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/person_test.exs test/media_centaur/social/profile_test.exs`
Expected: FAIL — `save_profile/3` undefined, `Person.hue/1` undefined.

- [ ] **Step 3: The Person**

In `lib/media_centaur/social/person.ex`: add `:published_hue, :hue_override` to the `defstruct` list (after `:avatar_url`), the types `published_hue: Hue.t() | nil, hue_override: Hue.t() | nil` (alias `MediaCentaur.Social.Hue`), a moduledoc sentence "`published_hue` is the hue the key published, `hue_override` the reader's for a friend (UIDR-048); `hue/1` resolves them, nil when neither, and CSS draws the default." and:

```elixir
  @doc "The hue the reader sees: the override, else the published one, else nil (drawn as the default)."
  @spec hue(t()) :: Hue.t() | nil
  def hue(%__MODULE__{hue_override: override, published_hue: published}), do: override || published
```

- [ ] **Step 4: `Social`**

`people/0`: the select becomes `struct(p, [:pubkey, :name, :avatar_type, :hue, :created_at])` and the comment "Five fields per row". `own_person_for/2` gains `published_hue: profile && profile.hue`; `person_for/2` gains `published_hue: profile && profile.hue, hue_override: friend.hue_override`.

`save_profile/2` → `/3`:

```elixir
  @spec save_profile(String.t(), avatar_change(), Hue.t() | nil) ::
          {:ok, Profile.t()}
          | {:error, :name_required | :name_too_long | :avatar_too_large | :invalid_hue}
  def save_profile(name, avatar_change, hue) when is_binary(name) do
    with {:ok, name} <- check_name(name),
         :ok <- within_avatar_cap(avatar_change),
         :ok <- valid_hue(hue) do
      secret = Identity.ensure()
      me = Identity.pubkey()
      stored = Repo.get_by(Profile, pubkey: me)
      avatar = resolve_avatar(avatar_change, stored)
      created_at = Event.stamp_after(stored && stored.created_at, System.os_time(:second))

      event =
        %{name: name, avatar: avatar, hue: hue}
        |> ProfileTranslation.to_event(me, created_at)
        |> Event.sign(secret)

      {:ok, attrs} = ProfileTranslation.from_event(event)
      profile = store_profile(stored, attrs)
      Connections.publish(event)
      Events.broadcast(%Events.ProfileUpdated{pubkey: me})
      {:ok, profile}
    end
  end
```

Doc: add "The hue is the angle the circle takes (UIDR-048), nil for none; out of range is refused (`:invalid_hue`) before anything is minted." Update every `save_profile/2` mention in moduledocs (`Social`, `Profile`, `SocialSection`, `SettingsLive`'s comments) to `/3`. `lib/media_centaur_web/live/settings_live.ex:953`: `Social.save_profile(name, avatar, nil)` until Task 6.

- [ ] **Step 5: Run, expect green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/ test/media_centaur/relay_sync_test.exs test/media_centaur_web/live/settings_live_social_test.exs`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/social/person.ex lib/media_centaur/social.ex lib/media_centaur_web/live/settings_live.ex test/
git commit -m "feat: a Person carries the published hue and the reader's override; save_profile publishes the hue"
```

---

### Task 4: The tile draws its hue

**Files:**
- Modify: `assets/css/app.css` (`:root` after `--color-love`; a block before `.person-card`), `lib/media_centaur_web/components/discovery/identity_tile.ex`, `storybook/discovery/identity_tile.story.exs`
- Test: `test/media_centaur_web/components/discovery/identity_tile_test.exs`

- [ ] **Step 1: The test**

Add to `test/media_centaur_web/components/discovery/identity_tile_test.exs`:

```elixir
  test "the tile carries the person's hue as --hue, the override first; none sets no style" do
    none = render(person: person("cleo"), size: 40)
    assert none |> tile() |> LazyHTML.attribute("style") == []
    assert none |> tile() |> LazyHTML.attribute("data-hue") == []
    assert none |> tile() |> LazyHTML.attribute("class") |> hd() =~ "identity-tile-friend"

    published = render(person: %{person("cleo") | published_hue: 195}, size: 40)
    assert published |> tile() |> LazyHTML.attribute("style") == ["--hue: 195"]
    assert published |> tile() |> LazyHTML.attribute("data-hue") == ["195"]

    overridden = render(person: %{person("cleo") | published_hue: 195, hue_override: 12}, size: 40)
    assert overridden |> tile() |> LazyHTML.attribute("style") == ["--hue: 12"]

    own = render(person: %{own_person() | published_hue: 290}, size: 48)
    assert own |> tile() |> LazyHTML.attribute("style") == ["--hue: 290"]
    assert own |> tile() |> LazyHTML.attribute("class") |> hd() =~ "identity-tile-own"

    avatar = render(person: person("Ada", avatar_url: "/x.webp"), size: 48)
    assert avatar |> tile() |> LazyHTML.attribute("class") |> hd() =~ "identity-tile-avatar"
  end
```

- [ ] **Step 2: Run, expect the style and class assertions to fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/identity_tile_test.exs`
Expected: FAIL on `style`.

- [ ] **Step 3: The CSS**

In `assets/css/app.css`, in `:root` right after `--color-love: …;`:

```css
  /* A person's colour is a hue on one ring (UIDR-048): the theme fixes the
     lightness and chroma, the person picks the angle in `--hue`. */
  --person-l: 70%;
  --person-c: 0.15;
```

Before the `.person-card {` block:

```css
/* The identity tile (UIDR-046, UIDR-047, UIDR-048): one recipe over
   `--hue`, 250 (the primary's angle) when a person has none. A friend's
   mark in the hue on the hue at 20 % with a hairline; the reader's own
   filled in the hue with a near-white mark; a picture ringed outside
   its edge, 1 px for a friend and 2 px for the reader's own — outset,
   because an inset ring paints under the image. */
.identity-tile {
  --person: oklch(var(--person-l) var(--person-c) var(--hue, 250));
  --person-tint: oklch(var(--person-l) var(--person-c) var(--hue, 250) / 0.2);
  --person-hairline: oklch(var(--person-l) var(--person-c) var(--hue, 250) / 0.25);
}

.identity-tile-friend {
  background: var(--person-tint);
  color: var(--person);
  box-shadow:
    inset 0 0 0 1px var(--person-hairline),
    0 2px 8px oklch(0% 0 0 / 0.35);
}

.identity-tile-own {
  background: var(--person);
  color: oklch(97% 0.01 var(--hue, 250));
  box-shadow: 0 2px 8px oklch(0% 0 0 / 0.4);
}

.identity-tile-avatar.identity-tile-friend {
  background: none;
  box-shadow: 0 0 0 1px var(--person);
}

.identity-tile-avatar.identity-tile-own {
  background: none;
  box-shadow: 0 0 0 2px var(--person);
}
```

- [ ] **Step 4: The component**

In `identity_tile.ex`, the assigns gain `hue: Person.hue(assigns.person)`, and the root becomes:

```heex
    <span
      class={[
        "identity-tile relative grid shrink-0 place-items-center overflow-hidden rounded-full leading-none",
        @size_classes,
        if(@own?, do: "identity-tile-own font-bold", else: "identity-tile-friend font-semibold"),
        @mark == :avatar && "identity-tile-avatar"
      ]}
      style={@hue && "--hue: #{@hue}"}
      data-component="identity-tile"
      data-size={@size}
      data-own={@own?}
      data-mark={@mark}
      data-hue={@hue}
      aria-hidden="true"
    >
```

Delete the "The states are disjoint branches…" comment's first two sentences (the classes are now CSS); keep the size sentence. Moduledoc: replace "The reader's own tile is filled with the button primary and a white mark… an avatar inside a 2px primary ring says the same." with "The tile draws in the person's hue (`Person.hue/1`, UIDR-048), the primary's angle when they have none: a friend's mark in the hue on its tint, the reader's own filled in it with a near-white mark, a picture ringed in it, 1 px for a friend and 2 px for the reader's own. The recipe is `.identity-tile*` in `app.css`."

- [ ] **Step 5: The story**

In `storybook/discovery/identity_tile.story.exs`, add a third `VariationGroup` after `:page_48`:

```elixir
      %VariationGroup{
        id: :hues,
        description:
          "The palette (UIDR-048): a friend's letter at every hue, then the reader's own, then a picture ringed in the hue; the first tile has no hue and is the default Blue",
        variations:
          [
            %Variation{id: :none, attributes: %{person: friend("Cleo"), size: 48}}
          ] ++
            for {name, hue} <- Hue.palette() do
              %Variation{
                id: String.to_atom("friend_" <> String.downcase(name)),
                description: "#{name} #{hue}",
                attributes: %{person: %{friend("Cleo") | published_hue: hue}, size: 48}
              }
            end ++
            for {name, hue} <- Hue.palette() do
              %Variation{
                id: String.to_atom("own_" <> String.downcase(name)),
                attributes: %{person: %Person{pubkey: @me, own?: true, published_hue: hue}, size: 48}
              }
            end ++
            [
              %Variation{
                id: :avatar_teal,
                description: "A friend's picture ringed in Teal; the override wins over the published Rose",
                attributes: %{
                  person: %{friend("Ada") | avatar_url: @photo, published_hue: 12, hue_override: 195},
                  size: 48
                }
              },
              %Variation{
                id: :own_avatar_violet,
                attributes: %{person: %Person{pubkey: @me, own?: true, avatar_url: @photo, published_hue: 290}, size: 48}
              }
            ]
      }
```

with `alias MediaCentaur.Social.Hue` added. Storybook variation ids must be atoms: the `String.to_atom` calls above run at compile time over eight fixed names.

- [ ] **Step 6: Run, expect green; look at it**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/identity_tile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: 0 failures.

Then `~/scripts/agents/page-shot --url http://localhost:2160/storybook/discovery/identity_tile --wait-ms 3000 --viewport 1600x1400 -o /tmp/claude-1000/…/scratchpad/tile-hues.png` and Read it: eight friend tints, eight own fills, the ringed pictures; the first tile identical to the old primary look.

- [ ] **Step 7: Commit**

```bash
git add assets/css/app.css lib/media_centaur_web/components/discovery/identity_tile.ex storybook/discovery/identity_tile.story.exs test/media_centaur_web/components/discovery/identity_tile_test.exs
git commit -m "feat: the identity tile draws in the person's hue; one CSS recipe over --hue with the primary's angle as the default"
```

---

### Task 5: `HueSwatches`, the swatch row and the ring slider

**Files:**
- Create: `lib/media_centaur_web/components/discovery/hue_swatches.ex`, `storybook/discovery/hue_swatches.story.exs`, `test/media_centaur_web/components/discovery/hue_swatches_test.exs`
- Modify: `assets/css/app.css` (after the `.identity-tile` block)

- [ ] **Step 1: The test**

```elixir
defmodule MediaCentaurWeb.Components.Discovery.HueSwatchesTest do
  use MediaCentaur.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Discovery.HueSwatches

  defp render(attrs) do
    LazyHTML.from_fragment(render_component(&HueSwatches.hue_swatches/1, Map.merge(%{id: "hues", event: "pick"}, attrs)))
  end

  defp swatches(html), do: LazyHTML.query(html, "[data-component='hue-swatches'] button[data-hue]")

  test "eight palette swatches, each a nav item pushing the event with its hue and the caller's values; the chosen one is pressed" do
    html = render(%{selected: 195, values: %{"pubkey" => "abc"}})
    swatches = swatches(html)

    assert Enum.count(swatches) == 8
    assert LazyHTML.attribute(swatches, "phx-click") |> Enum.uniq() == ["pick"]
    assert LazyHTML.attribute(swatches, "phx-value-pubkey") |> Enum.uniq() == ["abc"]
    assert LazyHTML.attribute(swatches, "phx-value-hue") == ~w(12 45 80 150 195 250 290 335)
    assert LazyHTML.attribute(swatches, "style") |> hd() == "--hue: 12"
    assert LazyHTML.attribute(swatches, "aria-label") |> hd() == "Rose"
    assert LazyHTML.attribute(swatches, "data-nav-item") |> length() == 8

    pressed = LazyHTML.query(html, "button[data-hue][aria-pressed='true']")
    assert LazyHTML.attribute(pressed, "data-hue") == ["195"]
  end

  test "the slider is a form field named hue at the chosen angle, with the ring as its track" do
    slider = render(%{selected: 195}) |> LazyHTML.query("input[type='range'][name='hue']")
    assert LazyHTML.attribute(slider, "value") == ["195"]
    assert LazyHTML.attribute(slider, "min") == ["0"]
    assert LazyHTML.attribute(slider, "max") == ["359"]
    assert LazyHTML.attribute(slider, "aria-label") == ["Any colour"]
    assert LazyHTML.attribute(slider, "phx-debounce") == ["150"]
    refute LazyHTML.query(render(%{selected: 195}), "form") |> Enum.any?()
  end

  test "Theirs leads the row when asked, in the published hue, pushing an empty hue; pressed when nothing is chosen" do
    html = render(%{selected: nil, theirs?: true, theirs_hue: 12})
    theirs = LazyHTML.query(html, "button[data-role='theirs']")
    assert LazyHTML.attribute(theirs, "aria-pressed") == ["true"]
    assert LazyHTML.attribute(theirs, "phx-value-hue") == [""]
    assert LazyHTML.attribute(theirs, "style") == ["--hue: 12"]
    assert LazyHTML.attribute(theirs, "aria-label") == ["Theirs"]
    assert html |> LazyHTML.query("input[type='range']") |> LazyHTML.attribute("value") == ["12"]

    overridden = render(%{selected: 195, theirs?: true, theirs_hue: 12})
    assert overridden |> LazyHTML.query("button[data-role='theirs']") |> LazyHTML.attribute("aria-pressed") == ["false"]

    no_published = render(%{selected: nil, theirs?: true, theirs_hue: nil})
    assert no_published |> LazyHTML.query("button[data-role='theirs']") |> LazyHTML.attribute("style") == []
    assert no_published |> LazyHTML.query("input[type='range']") |> LazyHTML.attribute("value") == ["250"]

    refute render(%{selected: 195}) |> LazyHTML.query("button[data-role='theirs']") |> Enum.any?()
  end
end
```

- [ ] **Step 2: Run, expect the module missing**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/hue_swatches_test.exs`
Expected: FAIL, undefined.

- [ ] **Step 3: The component**

```elixir
defmodule MediaCentaurWeb.Components.Discovery.HueSwatches do
  @moduledoc """
  The one place a hue is chosen (UIDR-048): the palette as round
  swatches in ring order, the chosen one pressed, and under them the
  ring itself as a slider, its thumb at the chosen angle. A swatch is a
  button pushing `event` with the caller's `values` and `hue`; the
  slider is a form field named `hue` and carries no event of its own —
  the host's enclosing form's `phx-change` receives it (Settings' profile
  form; a small `set_hue_override` form on a friend's card foot), so a
  click and a drag reach one handler with one payload. Every swatch and
  the slider are nav items.

  `theirs?` leads the row with **Theirs**, the friend's published hue
  (`theirs_hue`; the default Blue when nil), pressed while `selected` is
  nil and pushing an empty `hue` to clear the override.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [phx_values: 1]

  alias MediaCentaur.Social.Hue

  attr :id, :string, required: true
  attr :selected, :integer, default: nil, doc: "the chosen hue; nil is none (Theirs, when shown)"
  attr :theirs?, :boolean, default: false, doc: "lead with the friend's published hue"
  attr :theirs_hue, :integer, default: nil, doc: "the published hue Theirs draws; nil draws the default"
  attr :event, :string, required: true, doc: "pushed by a swatch with `values` and `hue`"
  attr :values, :map, default: %{}, doc: "phx-value-* params a swatch carries beside `hue`"
  attr :class, :any, default: nil
  attr :rest, :global

  def hue_swatches(assigns) do
    assigns = assign(assigns, thumb: assigns.selected || assigns.theirs_hue || 250)

    ~H"""
    <div id={@id} class={["space-y-2", @class]} data-component="hue-swatches" {@rest}>
      <div class="flex flex-wrap items-center gap-2.5">
        <button
          :if={@theirs?}
          type="button"
          class="hue-swatch"
          style={@theirs_hue && "--hue: #{@theirs_hue}"}
          aria-pressed={to_string(is_nil(@selected))}
          aria-label="Theirs"
          title="Theirs"
          phx-click={@event}
          {phx_values(Map.put(@values, "hue", ""))}
          data-role="theirs"
          data-nav-item
          tabindex="0"
        >
        </button>
        <button
          :for={{name, hue} <- Hue.palette()}
          type="button"
          class="hue-swatch"
          style={"--hue: #{hue}"}
          aria-pressed={to_string(@selected == hue)}
          aria-label={name}
          title={name}
          phx-click={@event}
          {phx_values(Map.put(@values, "hue", hue))}
          data-hue={hue}
          data-nav-item
          tabindex="0"
        >
        </button>
      </div>
      <input
        type="range"
        name="hue"
        min="0"
        max="359"
        value={@thumb}
        class="hue-slider"
        aria-label="Any colour"
        phx-debounce="150"
        data-nav-item
        tabindex="0"
      />
    </div>
    """
  end
end
```

CSS, after the `.identity-tile` block:

```css
/* The swatch row and the ring slider (UIDR-048). A swatch is the ring at
   its angle; the pressed one wears an outline. The slider's track is the
   whole ring. */
.hue-swatch {
  width: 28px;
  height: 28px;
  border-radius: 9999px;
  cursor: pointer;
  background: oklch(var(--person-l) var(--person-c) var(--hue, 250));
  box-shadow: 0 1px 3px oklch(0% 0 0 / 0.4);
}

.hue-swatch[aria-pressed="true"] {
  outline: 2px solid var(--color-base-content);
  outline-offset: 3px;
}

.hue-slider {
  appearance: none;
  width: 100%;
  max-width: 16rem;
  height: 12px;
  border-radius: 6px;
  background: linear-gradient(
    90deg,
    oklch(var(--person-l) var(--person-c) 0),
    oklch(var(--person-l) var(--person-c) 60),
    oklch(var(--person-l) var(--person-c) 120),
    oklch(var(--person-l) var(--person-c) 180),
    oklch(var(--person-l) var(--person-c) 240),
    oklch(var(--person-l) var(--person-c) 300),
    oklch(var(--person-l) var(--person-c) 360)
  );
}

.hue-slider::-webkit-slider-thumb {
  appearance: none;
  width: 18px;
  height: 18px;
  border-radius: 9999px;
  background: var(--color-base-content);
  border: 2px solid var(--color-base-200);
  cursor: pointer;
}
```

- [ ] **Step 4: The story**

```elixir
defmodule MediaCentaurWeb.Storybook.Discovery.HueSwatches do
  @moduledoc """
  The one place a hue is chosen (UIDR-048): eight palette swatches on
  the ring, the chosen one pressed, and the ring as a slider under them.
  On Settings the row picks the reader's own hue; on a friend's card
  foot it leads with Theirs, the friend's published hue, pressed while
  the reader has not chosen another.
  """

  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Discovery.HueSwatches.hue_swatches/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :settings,
        description: "Settings → Your profile: Teal chosen, the slider's thumb at 195",
        attributes: %{id: "hues-settings", selected: 195, event: "set_profile_hue"}
      },
      %Variation{
        id: :custom,
        description: "A hue off the palette from the slider: no swatch pressed, the thumb at 100",
        attributes: %{id: "hues-custom", selected: 100, event: "set_profile_hue"}
      },
      %Variation{
        id: :foot_theirs,
        description: "A friend's card foot: Theirs leads in the friend's Rose and is pressed; no override",
        attributes: %{id: "hues-theirs", selected: nil, theirs?: true, theirs_hue: 12, event: "set_hue_override"}
      },
      %Variation{
        id: :foot_overridden,
        description: "The reader chose Violet over the friend's Rose",
        attributes: %{id: "hues-over", selected: 290, theirs?: true, theirs_hue: 12, event: "set_hue_override"}
      },
      %Variation{
        id: :foot_no_published,
        description: "A friend who published no hue: Theirs is the default Blue",
        attributes: %{id: "hues-none", selected: nil, theirs?: true, theirs_hue: nil, event: "set_hue_override"}
      }
    ]
  end
end
```

Add the story to `storybook/discovery/_discovery.index.exs` if that index lists entries by hand (read it; if it only names the folder, nothing to add).

- [ ] **Step 5: Run, expect green; look at it**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/hue_swatches_test.exs test/media_centaur_web/storybook_render_test.exs test/media_centaur_web/storybook_compile_test.exs`
Expected: 0 failures. Then a `page-shot` of `/storybook/discovery/hue_swatches` and Read it.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/discovery/hue_swatches.ex storybook/discovery/hue_swatches.story.exs test/media_centaur_web/components/discovery/hue_swatches_test.exs assets/css/app.css storybook/discovery/_discovery.index.exs
git commit -m "feat: HueSwatches, the swatch row and the ring slider"
```

---

### Task 6: Settings: the Colour row, the random seed, the name field

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live.ex` (mount assigns `:221-222`, `load_social/2` `:340-347`, `profile_name/0` `:354-359`, the social handlers `:935-975`, `handle_info` `:1603-1622`), `lib/media_centaur_web/live/settings_live/social_section.ex`
- Test: `test/media_centaur_web/live/settings_live_social_test.exs`

- [ ] **Step 1: The tests**

In `describe "profile"` of `test/media_centaur_web/live/settings_live_social_test.exs`:

```elixir
    test "a new profile's form starts on a palette hue; a swatch or the slider changes it; Save publishes it",
         %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      tile = "#profile-form [data-component='identity-tile']"
      [seed] = view |> element(tile) |> render() |> LazyHTML.from_fragment() |> LazyHTML.attribute("data-hue")
      assert String.to_integer(seed) in Enum.map(Hue.palette(), &elem(&1, 1))
      assert has_element?(view, "#profile-hues button[data-hue='#{seed}'][aria-pressed='true']")

      view |> element("#profile-hues button[data-hue='195']") |> render_click()
      assert has_element?(view, tile <> "[data-hue='195']")
      assert has_element?(view, "#profile-hues input[name='hue'][value='195']")

      view |> form("#profile-form", %{"hue" => "100"}) |> render_change(%{"_target" => ["hue"]})
      assert has_element?(view, tile <> "[data-hue='100']")
      refute has_element?(view, "#profile-hues button[aria-pressed='true']")

      view |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()
      assert %{hue: 100} = Social.own_profile()
      assert has_element?(view, tile <> "[data-hue='100']")
    end

    test "a saved hue loads as saved; a profile saved before hues seeds one for the form only", %{conn: conn} do
      {:ok, _profile} = Social.save_profile("Sample Name", :keep, 290)
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, "#profile-form [data-component='identity-tile'][data-hue='290']")
      assert has_element?(view, "#profile-hues button[data-hue='290'][aria-pressed='true']")

      {:ok, _profile} = Social.save_profile("Sample Name", :keep, nil)
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, "#profile-form [data-component='identity-tile'][data-hue]")
      assert %{hue: nil} = Social.own_profile()
    end

    test "the name field is 16rem with Save beside it, not the card's width", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)
      assert has_element?(view, "#profile-form input[name='name'].w-64")
      refute has_element?(view, "#profile-form input[name='name'].flex-1")
    end
```

Add `alias MediaCentaur.Social.Hue` to the test module.

- [ ] **Step 2: Run, expect failures**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_social_test.exs`
Expected: FAIL — no `#profile-hues`, no `data-hue`, `.w-64` absent.

- [ ] **Step 3: The LiveView**

In `settings_live.ex`:

mount (`:221-222`): `|> assign(profile_name: nil, profile_hue: nil, name_cap: …)`.

`load_social/2`: `|> assign(profile_name: profile_name(), profile_hue: profile_hue(), own_person: Social.own_person())`.

After `profile_name/0`:

```elixir
  # The form's hue (UIDR-048): the saved one, else a palette hue at random
  # so a new profile starts with a colour; the random one is the form's
  # alone until Save publishes it.
  defp profile_hue do
    case Social.own_profile() do
      %{hue: hue} when is_integer(hue) -> hue
      _none -> Hue.random()
    end
  end

  defp assign_hue(socket, value) do
    case Hue.parse(value) do
      {:ok, hue} when is_integer(hue) -> assign(socket, profile_hue: hue)
      _none_or_error -> socket
    end
  end
```

Handlers: replace the `validate_profile` clause with:

```elixir
  # The upload's change event: LiveView needs it bound to track the entry.
  # The slider is a field of the same form; a drag lands here as `hue`.
  def handle_event("validate_profile", %{"_target" => ["hue"], "hue" => hue}, socket),
    do: {:noreply, assign_hue(socket, hue)}

  def handle_event("validate_profile", _params, socket), do: {:noreply, socket}

  # A swatch: the form's pending hue, previewed in the card's tile.
  def handle_event("set_profile_hue", %{"hue" => hue}, socket), do: {:noreply, assign_hue(socket, hue)}
```

`save_profile`: `Social.save_profile(name, avatar, socket.assigns.profile_hue)`; on success the assigns gain `profile_hue: profile.hue`. Add the flash clause `{:error, :invalid_hue} -> {:noreply, put_flash(socket, :error, "That colour is not on the ring")}` (unreachable from the form, but the `with` must handle it).

`handle_info({:identity_changed, _})`: add `profile_hue: profile_hue()`. `handle_info({:profile_updated, _})`: `assign(socket, profile_name: profile_name(), profile_hue: saved_hue_or(socket.assigns.profile_hue), own_person: Social.own_person())` with:

```elixir
  # A friend's profile fires the same event; a pending hue is kept unless
  # the own row now carries one.
  defp saved_hue_or(pending) do
    case Social.own_profile() do
      %{hue: hue} when is_integer(hue) -> hue
      _none -> pending
    end
  end
```

Add `alias MediaCentaur.Social.Hue`. Pass `profile_hue={@profile_hue}` to `SocialSection.render/1` at both render sites (`:1858` and `:2060`).

- [ ] **Step 4: The section**

In `social_section.ex`: `attr :profile_hue, :integer, required: true, doc: "the form's pending hue (UIDR-048), previewed in the tile and published on Save"`. Alias `MediaCentaurWeb.Components.Discovery.HueSwatches`. `shown_person/2` gains the hue: the tile call becomes `person={shown_person(@own_person, @avatar_removed?, @profile_hue)}` with

```elixir
  defp shown_person(%Person{} = person, removed?, hue) do
    person = %{person | published_hue: hue}
    if removed?, do: %{person | avatar_url: nil}, else: person
  end
```

Between the upload entries and the name row insert:

```heex
          <div class="flex items-start gap-3">
            <span class="w-14 shrink-0 pt-1 text-sm text-base-content/70">Colour</span>
            <HueSwatches.hue_swatches
              id="profile-hues"
              selected={@profile_hue}
              event="set_profile_hue"
              class="min-w-0 flex-1"
            />
          </div>
```

The name row: `<div class="flex items-start gap-3"><span class="w-14 shrink-0 pt-2 text-sm text-base-content/70">Name</span>` then the input with `class="w-64"` (replacing `min-w-0 flex-1`) and the Save button as before, closing the div. Moduledoc: "…the picture beside it, the colour the circle takes (`HueSwatches`, starting on a palette hue at random), one form whose save…"; handlers list gains `set_profile_hue`.

- [ ] **Step 5: Run, expect green**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_social_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: 0 failures.

Then `page-shot --url http://localhost:2160/settings?section=social --wait-ms 3000 --viewport 1920x1080` and Read it: the Colour row between the picture and the name, the name field short with Save beside it.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/live/settings_live.ex lib/media_centaur_web/live/settings_live/social_section.ex test/media_centaur_web/live/settings_live_social_test.exs
git commit -m "feat: choose a colour on Settings; a new profile starts on a palette hue; the name field is 16rem with Save beside it"
```

---

### Task 7: The card foot's Colour row; the Discovery handler

**Files:**
- Modify: `lib/media_centaur_web/components/discovery/person_card.ex`, `lib/media_centaur_web/live/discovery_live.ex:262-268`, `storybook/discovery/person_card.story.exs`
- Test: `test/media_centaur_web/components/discovery/person_card_test.exs`, `test/media_centaur_web/live/discovery_live_test.exs`

- [ ] **Step 1: The component test**

In `person_card_test.exs`, after the switch test:

```elixir
  test "the foot's Colour row: Theirs in the published hue, the palette, the slider in a form saving on the act; the rename field is 16rem" do
    html = render(person: person("Nick", published_hue: 12, hue_override: 195), acts: [], width: :page, opened?: true)
    form = LazyHTML.query(html, "footer form[data-role='hue-form']")

    assert LazyHTML.attribute(form, "phx-change") == ["set_hue_override"]
    assert LazyHTML.attribute(form, "phx-click") == [""]
    assert form |> LazyHTML.query("input[type='hidden'][name='pubkey']") |> LazyHTML.attribute("value") == [person("Nick").pubkey]

    theirs = LazyHTML.query(form, "button[data-role='theirs']")
    assert LazyHTML.attribute(theirs, "style") == ["--hue: 12"]
    assert LazyHTML.attribute(theirs, "aria-pressed") == ["false"]
    assert LazyHTML.attribute(theirs, "phx-click") == ["set_hue_override"]
    assert LazyHTML.attribute(theirs, "phx-value-pubkey") == [person("Nick").pubkey]

    assert form |> LazyHTML.query("button[data-hue='195']") |> LazyHTML.attribute("aria-pressed") == ["true"]
    assert form |> LazyHTML.query("input[type='range'][name='hue']") |> LazyHTML.attribute("value") == ["195"]

    assert html |> LazyHTML.query("footer [data-role='name-form'] input[name='name']") |> LazyHTML.attribute("class") |> hd() =~ "basis-64"
  end
```

`DiscoveryRows.person/2` must accept `published_hue:` and `hue_override:` — add to its `%Person{}`: `published_hue: Keyword.get(opts, :published_hue), hue_override: Keyword.get(opts, :hue_override)` and the two to its doc.

- [ ] **Step 2: The live test**

In `discovery_live_test.exs`, after the *Show their picture* test:

```elixir
    test "the foot's Colour row saves on the act: a swatch overrides the published hue, Theirs clears it, the slider sets any angle",
         %{conn: conn} do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Ada")
      {:ok, _profile} = Social.ingest_profile(friend_profile("Ada", 1_700_000_000, nil, 12))

      {:ok, view, _html} = live(conn, "/discovery/friends")
      tile = friend_card() <> " [data-component='identity-tile']"
      form = friend_card() <> " footer form[data-role='hue-form']"
      assert has_element?(view, tile <> "[data-hue='12']")

      view |> element(friend_card()) |> render_click()
      assert has_element?(view, form <> " button[data-role='theirs'][aria-pressed='true']")

      view |> element(form <> " button[data-hue='195']") |> render_click()
      assert has_element?(view, tile <> "[data-hue='195']")
      assert %{hue_override: 195} = Social.friend_by_pubkey(@friend_pubkey)

      view |> form(form, %{"hue" => "100"}) |> render_change(%{"_target" => ["hue"]})
      assert has_element?(view, tile <> "[data-hue='100']")
      assert %{hue_override: 100} = Social.friend_by_pubkey(@friend_pubkey)

      view |> element(form <> " button[data-role='theirs']") |> render_click()
      assert has_element?(view, tile <> "[data-hue='12']")
      assert %{hue_override: nil} = Social.friend_by_pubkey(@friend_pubkey)
    end
```

`friend_profile/3` at `:194` gains an optional fourth argument: `defp friend_profile(name, at, avatar \\ nil, hue \\ nil)` building `ProfileTranslation.to_event(%{name: name, avatar: avatar, hue: hue}, @friend_pubkey, at)`.

- [ ] **Step 3: Run, expect failures**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/person_card_test.exs test/media_centaur_web/live/discovery_live_test.exs`
Expected: FAIL — no `hue-form`.

- [ ] **Step 4: The card and the handler**

In `person_card.ex`, alias `MediaCentaurWeb.Components.Discovery.HueSwatches`; after the `Switch.switch` in the footer:

```heex
        <form
          id={"#{@id}-hue-form"}
          phx-change="set_hue_override"
          phx-click={%JS{}}
          class="space-y-1"
          data-role="hue-form"
        >
          <input type="hidden" name="pubkey" value={@person.pubkey} />
          <span class="block text-sm">Colour</span>
          <HueSwatches.hue_swatches
            id={"#{@id}-hues"}
            selected={@person.hue_override}
            theirs?
            theirs_hue={@person.published_hue}
            event="set_hue_override"
            values={%{"pubkey" => @person.pubkey}}
          />
        </form>
```

The rename input's class: `basis-64` for `basis-48`. Moduledoc: after the avatar switch sentence add "the **Colour** row (`HueSwatches`, UIDR-048): Theirs, the friend's published hue, then the palette and the ring, saving on the act (`set_hue_override` with the key and the hue, empty for Theirs; the slider through the row's own form)".

In `discovery_live.ex` after `set_show_avatar`:

```elixir
  # The opened card's foot: the reader's hue for the friend; empty is
  # Theirs, clearing it. A swatch's click and the slider's change carry
  # the same two keys.
  def handle_event("set_hue_override", %{"pubkey" => pubkey, "hue" => hue}, socket) do
    with {:ok, hue} <- Hue.parse(hue),
         {:ok, _friend} <- Social.set_hue_override(pubkey, hue) do
      {:noreply, socket}
    else
      {:error, :not_a_friend} -> {:noreply, flash_not_a_friend(socket)}
      _bad_hue -> {:noreply, socket}
    end
  end
```

with `alias MediaCentaur.Social.Hue`.

- [ ] **Step 5: The story**

In `person_card.story.exs`, after `:page_opened_avatar_hidden`:

```elixir
      %Variation{
        id: :page_opened_hue,
        description:
          "The opened card of a friend who published Rose, which the reader overrode with Teal: the tile in Teal, Theirs in Rose, Teal pressed",
        attributes: %{
          person: %{friend() | published_hue: 12, hue_override: 195},
          acts: seven_acts(),
          width: :page,
          opened?: true
        },
        template: @page
      },
```

- [ ] **Step 6: Run, expect green; look at it**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/ test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: 0 failures. `page-shot` of `/storybook/discovery/person_card` (the `page_opened_hue` variation) and Read it.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web/components/discovery/person_card.ex lib/media_centaur_web/live/discovery_live.ex storybook/discovery/person_card.story.exs test/support/discovery_rows.ex test/media_centaur_web/components/discovery/person_card_test.exs test/media_centaur_web/live/discovery_live_test.exs
git commit -m "feat: the card's foot chooses the reader's colour for a friend; Theirs restores the published one"
```

---

### Task 8: The whole suite and `precommit`

- [ ] Run `~/scripts/agents/agent-mix precommit` (use `agent-output` to capture it). Fix everything: format, Credo (MC0009 for the new story, MC0034 for any text under /55), boundaries, warnings, the suite. Commit as `chore: precommit clean after the hue`.

---

### Task 9: Docs, protocol page, wiki, glossary, campaign

**Files:**
- Modify: `docs/social-protocol.md` (§ Profile's content table and rules; § Changes), `docs/social.md` (the Person and the profile rows; `:start_relay_sync`), `docs/GLOSSARY.md` (§ Social: **Hue**, **Palette**, **Hue override**, **Theirs**; the **Friend**, **Profile** and **Person** rows mention the hue), `docs/architecture.md` if it names the sync key, `campaigns/profiles.md` (Status, Decisions made: 5a as built, Next steps: 5b), `campaigns/README.md`, the wiki: `../media-centaur.wiki/Social.md` (Your profile's colour; a friend's card foot's Colour row and Theirs) and `Settings-Reference.md` (the Social section's profile card), commit and push the wiki.

- [ ] Protocol page § Profile, content table, after `avatar`:

```
| `hue` | integer | 0–359 | The angle on the oklch ring at which the person's circle is drawn; the reader supplies lightness and chroma. Optional: absent or `null` means the person gives none. |
```

Rules: "A `hue` that is not an integer, or is out of 0–359, drops the whole profile (a JSON number with a fraction is not an integer)." Changes row: `| 2026-09-28 | Profile `hue`, an integer 0–359, optional: the person's colour as an angle on one oklch ring, drawn at the reader's lightness and chroma (UIDR-048). No relay change. |`

- [ ] Glossary rows, in the spec's words (§ Phase 5 Glossary, continued), each naming its module or column.

- [ ] Campaign: Status "5a shipped on `main` (unreleased)"; a Decisions entry "5a as built" naming any departure from this plan; Next steps → 5b. README entry updated.

- [ ] Commit: `docs: the hue on the protocol page, in the guides, the glossary and the wiki; profiles phase 5a as built`.

---

## Self-review (2026-09-28)

**Spec coverage.** The hue's ring and palette → Task 1 (`Hue`) and Task 4 (CSS); the wire → Task 1; storage → Tasks 1–2; the read model → Task 3; the tile → Task 4; choosing → Tasks 5–7; the random seed → Task 6; the name field → Tasks 6 (Settings) and 7 (the card); errors → Tasks 2, 3, 6; the migration incl. the `nickname` drop and the sync key → Task 2; testing → each task; docs → Task 9. The crop is phase 5b, not here.

**Type consistency.** `to_event/3` takes `%{name, avatar, hue}` everywhere (Tasks 1, 3, 7's helper). `save_profile/3` takes `(name, avatar_change, hue)` (Tasks 3, 6, tests). `Person.hue/1`, `published_hue`, `hue_override` (Tasks 3–7). `HueSwatches` attrs `id`, `selected`, `theirs?`, `theirs_hue`, `event`, `values`, `class` (Tasks 5–7). Events: `set_profile_hue` (Settings), `set_hue_override` (Discovery); both payloads carry `hue`, the second also `pubkey`. `Hue.parse/1` returns `{:ok, hue | nil} | :error` (Tasks 1, 6, 7).
