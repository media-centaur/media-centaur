# Profiles, phase 1: the roster and the Person read model. Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One representation of a person in the app, `Social.Person`, read by every surface; a friend's name is renamed from the card; the identity tile takes a Person. No wire change and no schema change: this phase ships on its own as a whole product.

**Architecture:** `Social.people/0` builds `%{pubkey => Person}` for the identity and the roster. `Activities` keeps the enriched-list join it owns but puts a Person on every row as `author` and drops rows by unknown authors. Every web surface takes a Person and renders its words through `MediaCentaur.Format.person_name/1` ("You" or the name). The web `Components.Discovery.Person` struct is retired; `PersonCard` takes `person` and `acts`. The roster field is renamed in code to `name_override` over the existing `nickname` column with Ecto's `source:`; the column converges in phase 2's rebuild, when the name becomes optional beside the published one.

**Tech Stack:** Elixir 1.20 / Phoenix LiveView, Ecto with `ecto_sqlite3`, Phoenix Storybook, ExUnit + LazyHTML, Credo + Boundary.

**Design:** `docs/superpowers/specs/2026-09-27-profiles-design.md`, ADR-073, ADR-074, UIDR-047. Campaign: `campaigns/profiles.md`. The unify pass of 2026-09-27 re-sequenced the phases: every shipped state is a whole product, and nothing in a phase exists for a later one.

---

## Read before starting

- **Never run `mix` directly.** Every command below is `~/scripts/agents/agent-mix …`. The dev daily driver compiles into this checkout's `_build/dev`; a bare `mix` takes it down.
- **Test first.** Every task writes or rewrites its tests before the code, runs them red, then green.
- **The suite is red between Task 1 and Task 10 by design.** The row shape `%{activity, author}` replaces `%{activity, nickname, own?}` everywhere at once; tasks land it bottom-up, and each task's own tests are green at its commit. Task 11 runs the whole suite and `precommit`. Work on `main`, commit per task, do not push.
- **Commit messages**: conventional (`feat:`, `refactor:`, `test:`, `docs:`), body in plain prose. End with the session's attribution trailer the harness gives you. Never `Co-Authored-By`.
- **Copy**: every user-facing string introduced here ("Rename", "Your name for this friend") goes through the `writing-copy` skill before the task's commit. The strings in this plan are the working versions.
- **Storybook**: MC0009 requires a story per function component; `storybook_compile_test` and `storybook_render_test` in `mix test` render every story. A story's filename is pinned to the component function, so do not rename story files.
- **Zero warnings.** A warning is a bug. `mix_unused` runs in `precommit`: a public function with no caller fails it, which is why nothing here is built for a later phase.
- `Library.Person` already exists (a title's cast member). The new struct is `MediaCentaur.Social.Person`; where both are in scope, alias the new one `as: SocialPerson`. In this phase no file needs both.

## What this phase does not do, on purpose

Recorded here so the phase 2 and 3 plans open with them:

- **Phase 2**, with the profile event: the `friends` rebuild (`name_override` as a real nullable column beside a nullable `nickname` the outgoing release still reads; `nickname` dropped the release after); the name optional in `add_friend/2`, `set_name_override/2` and the add form; `Person.published_name` and `Person.name/1` (override, else published, else nil); `Format.person_name/1` saying "Unnamed" for a nil name; the identity tile's third mark, the person glyph; the foot's placeholder as the person's words without the override, `Format.person_name(%Person{person | name_override: nil})`, never a literal.
- **Phase 3**, with the avatar: `show_avatar` as a plain `add` column (no rebuild needed), `Social.set_show_avatar/2`, the card's switch, `Person.avatar_url` filled.

One named exception to "nothing in a phase exists for a later one": `Person.avatar_url` and the tile's `:avatar` mark have no writer in phase 1. They carry the photo state UIDR-046 shipped and the storybook pinned before this campaign; removing a shipped, decided render state to satisfy the letter of the rule would be churn, and phase 3 fills the field. `published_name` and `show_avatar` had no prior existence, which is why they wait.

## File structure

Created:

- `lib/media_centaur/social/person.ex`: the read model struct.
- `lib/media_centaur_web/components/discovery/act.ex`: `Act` and `Act.Entry`, moved out of the retired web `Person`.
- `test/media_centaur/social/person_test.exs`.

Modified (one responsibility each):

- `lib/media_centaur/social/friend.ex`, `lib/media_centaur/social.ex`, `lib/media_centaur/social/events.ex`: the field rename, the API, `FriendChanged`, `people/0`.
- `lib/media_centaur/format.ex`: `person_name/1`.
- `lib/media_centaur/activities.ex`: rows carry `author`.
- `test/support/discovery_rows.ex`: fixtures build Persons.
- `lib/media_centaur_web/components/discovery/identity_tile.ex`: takes a Person.
- `lib/media_centaur_web/components/discovery/feed_entry.ex`, `lib/media_centaur_web/live/discovery_live/feed_entries.ex`, `lib/media_centaur_web/components/discovery/feed_row.ex`.
- `lib/media_centaur_web/components/title/pennant.ex`.
- `lib/media_centaur_web/components/detail_panel.ex`, `lib/media_centaur_web/live/review_modal.ex`.
- `lib/media_centaur_web/live/discovery_live/people.ex`, `lib/media_centaur_web/components/discovery/person_card.ex`.
- `lib/media_centaur_web/live/discovery_live.ex`, `lib/media_centaur_web/live/discovery_live/add_friend_block.ex`.
- Stories: `storybook/discovery/{identity_tile,person_card,feed_row}.story.exs`, `storybook/title/{pennants,title_row}.story.exs`, `storybook/acquisition/media_results.story.exs`, `storybook/composites/cinematic_shell.story.exs`, `storybook/detail_panel/detail_panel.story.exs`.
- Docs: `docs/social.md`, `lib/media_centaur/topics.ex` (table), the spec, `campaigns/profiles.md`, wiki `Social.md`.

Deleted:

- `lib/media_centaur_web/components/discovery/person.ex`.

---

### Task 1: `Friend.name_override` over the `nickname` column, and the roster API

**Files:**
- Modify: `lib/media_centaur/social/friend.ex`
- Modify: `lib/media_centaur/social.ex:1-15` (Boundary exports), `:76-160` (friend functions)
- Modify: `lib/media_centaur/social/events.ex`
- Test: `test/media_centaur/social/friend_test.exs`

No migration. The field is renamed in code with `source: :nickname`; the column is renamed by phase 2's rebuild, when the name becomes optional. The name stays required here, because nothing can publish a name yet for it to fall back on. Re-adding a key already on the roster changes nothing, as adding a relay you already have does; the card's foot is the one place to rename.

- [ ] **Step 1: Rewrite the friend tests**

Replace the whole of `test/media_centaur/social/friend_test.exs` with:

```elixir
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
```

- [ ] **Step 2: Run them red**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/friend_test.exs`
Expected: FAIL. `FriendChanged` is undefined, `name_override` is not a field, `set_name_override/2` does not exist.

- [ ] **Step 3: The schema**

Replace `lib/media_centaur/social/friend.ex` with:

```elixir
defmodule MediaCentaur.Social.Friend do
  @moduledoc """
  One followed public key: the x-only key as lowercase hex and the
  reader's name for it, `name_override` (UIDR-047): the reader's own
  word for the friend, which will mask the name the key publishes once
  profiles carry one. Nothing here comes from the network.

  The column is still `nickname`, mapped with `source:`; the profiles
  campaign's phase 2 rebuild renames it when the name becomes optional
  beside the published one.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "friends" do
    field :pubkey, :string
    field :name_override, :string, source: :nickname

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for a roster row; the pubkey must already be lowercase hex."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(friend \\ %__MODULE__{}, attrs) do
    friend
    |> cast(attrs, [:pubkey, :name_override])
    |> update_change(:name_override, &String.trim/1)
    |> validate_required([:pubkey, :name_override])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint(:pubkey)
  end
end
```

- [ ] **Step 4: The event**

In `lib/media_centaur/social/events.ex`:

Replace the `FriendAdded` moduledoc line with:

```elixir
    @moduledoc "A public key joined the roster."
```

Add after the `FriendAdded` module:

```elixir
  defmodule FriendChanged do
    @moduledoc "The reader's choices for a roster key changed: today the name override."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end
```

Add `| FriendChanged.t()` to the `@type t` union, and this clause among the `broadcast/1` clauses:

```elixir
  def broadcast(%FriendChanged{} = event), do: publish({:friend_changed, event})
```

- [ ] **Step 5: The context**

In `lib/media_centaur/social.ex`, add `Events.FriendChanged,` to the Boundary `exports` list (alphabetical: after `Events.FriendAdded`).

Replace everything from the `add_friend/2` `@doc` through `rename_friend/2` (lines 76–160 today) with:

```elixir
  @doc """
  Adds a friend by npub or 64-hex key under the reader's name for them
  (UIDR-047). Idempotent on the key: re-adding one already on the roster
  changes nothing, as adding a relay you already have does; the name is
  changed with `set_name_override/2`.
  """
  @spec add_friend(String.t(), String.t()) ::
          {:ok, Friend.t()}
          | {:error, :invalid_pubkey | :name_required | :own_key | Ecto.Changeset.t()}
  def add_friend(key, name) when is_binary(key) and is_binary(name) do
    with {:ok, pubkey} <- Keys.parse_pubkey(String.trim(key)),
         :ok <- not_own_key(pubkey),
         {:ok, name} <- present_name(name) do
      case Repo.get_by(Friend, pubkey: pubkey) do
        %Friend{} = existing -> {:ok, existing}
        nil -> insert_friend(pubkey, name)
      end
    end
  end

  @doc """
  Sets the reader's name for a friend. Broadcasts `FriendChanged` when it
  changed; the same name again is silent.
  """
  @spec set_name_override(String.t(), String.t()) ::
          {:ok, Friend.t()} | {:error, :name_required | :not_a_friend | Ecto.Changeset.t()}
  def set_name_override(pubkey, name) when is_binary(pubkey) and is_binary(name) do
    with {:ok, name} <- present_name(name),
         {:ok, friend} <- known_friend(pubkey) do
      apply_change(friend, %{name_override: name})
    end
  end

  @doc "Removes a friend by public key. Absent is a no-op, and broadcasts nothing."
  @spec remove_friend(String.t()) :: :ok
  def remove_friend(pubkey) when is_binary(pubkey) do
    case Repo.get_by(Friend, pubkey: String.downcase(pubkey)) do
      nil ->
        :ok

      friend ->
        Repo.delete!(friend)
        Events.broadcast(%Events.FriendRemoved{pubkey: friend.pubkey})
        :ok
    end
  end

  @doc "The roster, oldest first."
  @spec list_friends() :: [Friend.t()]
  def list_friends,
    do: Repo.all(from(friend in Friend, order_by: [friend.inserted_at, friend.pubkey]))

  @doc "One friend by public key, or nil."
  @spec friend_by_pubkey(String.t()) :: Friend.t() | nil
  def friend_by_pubkey(pubkey) when is_binary(pubkey),
    do: Repo.get_by(Friend, pubkey: String.downcase(pubkey))

  @doc """
  The NIP-19 `npub` form of a public key. The context owns the key
  vocabulary; the web layer never reaches into `Nostr.Keys` itself.
  """
  @spec to_npub(String.t()) :: String.t()
  def to_npub(pubkey) when is_binary(pubkey), do: Keys.to_npub(pubkey)

  @doc "Every followed pubkey — the authors the activities feed subscribes to."
  @spec friend_pubkeys() :: [String.t()]
  def friend_pubkeys,
    do: Repo.all(from(friend in Friend, select: friend.pubkey, order_by: friend.pubkey))

  defp not_own_key(pubkey), do: if(Identity.pubkey() == pubkey, do: {:error, :own_key}, else: :ok)

  defp present_name(name) do
    case String.trim(name) do
      "" -> {:error, :name_required}
      trimmed -> {:ok, trimmed}
    end
  end

  defp known_friend(pubkey) do
    case friend_by_pubkey(pubkey) do
      nil -> {:error, :not_a_friend}
      friend -> {:ok, friend}
    end
  end

  defp insert_friend(pubkey, name) do
    case Repo.insert(Friend.changeset(%{pubkey: pubkey, name_override: name})) do
      {:ok, friend} ->
        Events.broadcast(%Events.FriendAdded{pubkey: friend.pubkey})
        {:ok, friend}

      {:error, changeset} ->
        # A concurrent insert of the same key is the re-add case, not a failure.
        if unique_violation?(changeset),
          do: {:ok, Repo.get_by!(Friend, pubkey: pubkey)},
          else: {:error, changeset}
    end
  end

  # No change is no broadcast.
  defp apply_change(%Friend{} = existing, attrs) do
    changeset = Friend.changeset(existing, attrs)

    if changeset.changes == %{} do
      {:ok, existing}
    else
      with {:ok, friend} <- Repo.update(changeset) do
        Events.broadcast(%Events.FriendChanged{pubkey: friend.pubkey})
        {:ok, friend}
      end
    end
  end
```

Keep the existing private `unique_violation?/1` below. Delete `nickname_present/1`, `upsert_friend/2` and `rename_friend/2` if any trace remains.

Update the Social moduledoc's roster phrase to "the roster of followed keys under the reader's names for them (`Social.Friend`)".

- [ ] **Step 6: Run the friend tests green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/friend_test.exs`
Expected: PASS, 6 tests. The test database needs no new migration; `source:` reads and writes the `nickname` column.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur/social/friend.ex lib/media_centaur/social.ex lib/media_centaur/social/events.ex test/media_centaur/social/friend_test.exs
git commit -m "refactor: a friend's name is the reader's name_override over the nickname column; set_name_override and FriendChanged; re-adding a key is a no-op"
```

---

### Task 2: `Social.Person`, `people/0`, `own_person/0`, `Format.person_name/1`

**Files:**
- Create: `lib/media_centaur/social/person.ex`
- Modify: `lib/media_centaur/social.ex` (exports; new functions after `friend_pubkeys/0`)
- Modify: `lib/media_centaur/format.ex` (after `monogram/1`)
- Modify: `docs/superpowers/specs/2026-09-27-profiles-design.md` § The Person read model
- Test: `test/media_centaur/social/person_test.exs`

The struct carries what has a writer today: the key, the reader's name for a friend, the own flag, the short npub, the added date, and `avatar_url`, which carries the tile's existing photo contract (UIDR-046 pins it) and stays nil until phase 3. `published_name` and the resolver `Person.name/1` arrive with phase 2, when a published name exists.

- [ ] **Step 1: Write the tests**

```elixir
defmodule MediaCentaur.Social.PersonTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Format
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Person

  @friend "f9308a019258c31049344f85f89d5229b531c845836f99b08601f31bce036f9"
  @other "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

  describe "people/0" do
    test "the roster as people: the reader's name, no avatar" do
      {:ok, friend} = Social.add_friend(@friend, "Nick")
      {:ok, _friend} = Social.add_friend(@other, "Cleo")

      people = Social.people()

      assert map_size(people) == 2
      assert %Person{pubkey: @friend, name_override: "Nick", avatar_url: nil, own?: false} = people[@friend]
      assert people[@friend].short_npub == Social.short_npub(@friend)
      assert people[@friend].added_on == DateTime.to_date(friend.inserted_at)
      assert %Person{name_override: "Cleo", own?: false} = people[@other]
    end

    test "the reader is in the map once an identity exists, and is their own" do
      refute Enum.any?(Social.people(), fn {_pubkey, person} -> person.own? end)

      Identity.ensure()
      me = Identity.pubkey()

      assert %Person{pubkey: ^me, own?: true, name_override: nil, added_on: nil} = Social.people()[me]
    end
  end

  describe "own_person/0" do
    test "speaks as the reader before and after an identity exists" do
      assert %Person{pubkey: nil, own?: true} = Social.own_person()

      Identity.ensure()
      assert %Person{pubkey: pubkey, own?: true} = Social.own_person()
      assert pubkey == Identity.pubkey()
    end
  end

  test "Format.person_name/1 says You for the reader and the reader's name for a friend" do
    assert Format.person_name(%Person{pubkey: "me", own?: true}) == "You"
    assert Format.person_name(%Person{pubkey: @friend, name_override: "Nick"}) == "Nick"
  end

  test "short_npub/1 elides the middle" do
    short = Social.short_npub(@friend)

    assert String.starts_with?(short, "npub1")
    assert String.contains?(short, "…")
    assert String.length(short) == 14
  end
end
```

Use the real friend pubkey `f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9` for `@friend` (the constant above must be exactly that 64-hex value; copy it from `friend_test.exs`).

- [ ] **Step 2: Run them red**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/person_test.exs`
Expected: FAIL, `MediaCentaur.Social.Person` is not available.

- [ ] **Step 3: The struct**

Create `lib/media_centaur/social/person.ex`:

```elixir
defmodule MediaCentaur.Social.Person do
  @moduledoc """
  A public key as this reader sees it (ADR-074, UIDR-047): the reader's
  `name_override` for a friend (nil for the reader's own, who has no
  name here yet), the avatar URL (nil until the profiles campaign's
  phase 3 fills it; the tile already draws one), and whether the key is
  the reader's own. Built only by `Social.people/0` and
  `Social.own_person/0`; every surface that draws a person takes one.
  "You" is the web layer's word for `own?`
  (`MediaCentaur.Format.person_name/1`), never data here.

  `pubkey` is nil for the reader before an identity exists: the review
  modal previews as the reader all the same. `added_on` is nil for the
  reader's own.

  Not `MediaCentaur.Library.Person`, which is a title's cast member.
  """

  defstruct [:pubkey, :name_override, :avatar_url, :short_npub, :added_on, own?: false]

  @type t :: %__MODULE__{
          pubkey: String.t() | nil,
          name_override: String.t() | nil,
          avatar_url: String.t() | nil,
          own?: boolean(),
          short_npub: String.t() | nil,
          added_on: Date.t() | nil
        }
end
```

- [ ] **Step 4: The context functions**

In `lib/media_centaur/social.ex`, add `Person,` to the Boundary `exports` (alphabetical: after `Identity`) and `alias MediaCentaur.Social.Person` beside the other aliases. Add after `friend_pubkeys/0`:

```elixir
  @doc """
  Every person this reader knows, by public key (ADR-074): the identity's
  own when one exists, and every roster member, each as a `Person`.
  The one place a friend's roster row becomes what the reader sees.
  """
  @spec people() :: %{optional(String.t()) => Person.t()}
  def people do
    friends = Map.new(list_friends(), &{&1.pubkey, person_for(&1)})

    case Identity.pubkey() do
      nil -> friends
      me -> Map.put(friends, me, own_person_for(me))
    end
  end

  @doc """
  The reader as a person, with or without an identity: the review modal
  previews as the reader before a key exists.
  """
  @spec own_person() :: Person.t()
  def own_person, do: own_person_for(Identity.pubkey())

  @doc "The npub, elided in the middle: enough to compare against what a friend told you."
  @spec short_npub(String.t()) :: String.t()
  def short_npub(pubkey) when is_binary(pubkey) do
    npub = to_npub(pubkey)
    String.slice(npub, 0, 9) <> "…" <> String.slice(npub, -4..-1//1)
  end

  defp own_person_for(pubkey),
    do: %Person{pubkey: pubkey, own?: true, short_npub: pubkey && short_npub(pubkey)}

  defp person_for(%Friend{} = friend) do
    %Person{
      pubkey: friend.pubkey,
      name_override: friend.name_override,
      own?: false,
      short_npub: short_npub(friend.pubkey),
      added_on: DateTime.to_date(friend.inserted_at)
    }
  end
```

- [ ] **Step 5: The words**

In `lib/media_centaur/format.ex`, after `monogram/1`:

```elixir
  @doc """
  The words for a `MediaCentaur.Social.Person` (UIDR-047): "You" for the
  reader's own, else the reader's name for them. The one place "You"
  exists as a person's name.
  """
  @spec person_name(MediaCentaur.Social.Person.t()) :: String.t()
  def person_name(%MediaCentaur.Social.Person{own?: true}), do: "You"
  def person_name(%MediaCentaur.Social.Person{name_override: name}), do: name
```

- [ ] **Step 6: Run green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/person_test.exs test/media_centaur/social/friend_test.exs`
Expected: PASS.

- [ ] **Step 7: Amend the spec's Person block**

In `docs/superpowers/specs/2026-09-27-profiles-design.md`, replace the `%Social.Person{ … }` code block and the sentence after it with:

```elixir
%Social.Person{
  pubkey: hex | nil,                 # nil for the reader before an identity exists
  name_override: String.t() | nil,   # the reader's word for a friend; nil for the reader's own
  published_name: String.t() | nil,  # what the key said about itself (phase 2)
  avatar_url: String.t() | nil,      # nil when none, hidden, or the file is missing (phase 3)
  own?: boolean,
  short_npub: String.t() | nil,
  added_on: Date.t() | nil           # nil for the reader's own
}
```

followed by: "The struct grows with its writers. Phase 1 builds it with `name_override` required and `avatar_url` nil; phase 2 adds `published_name`, `Person.name/1` (the override, else the published name, else nil) and the optional override; phase 3 fills `avatar_url`. The card's foot shows the override with the published name as its placeholder, which is why both ride on the struct. `Social.people/0` returns `%{pubkey => Person}` for the identity (when one exists) and every roster member; `Social.own_person/0` is the reader with or without an identity."

In the glossary row for **Person**, append: "Carries the override and, from phase 2, the published name; `Person.name/1` resolves."

In § Build order, replace step 1 with: "**Roster and Person.** `Friend.name_override` over the `nickname` column with `source:`, `FriendChanged`, `Social.Person` and `people/0`, Activities rows carry `author`, every web site and story reads a Person, the override field on the card. No wire change, no schema change, the name still required." and prepend to step 2: "The `friends` rebuild and the optional name, Unnamed and the person glyph open this phase, since the published name is what a missing override falls back to."

- [ ] **Step 8: Commit**

```bash
git add lib/media_centaur/social/person.ex lib/media_centaur/social.ex lib/media_centaur/format.ex test/media_centaur/social/person_test.exs docs/superpowers/specs/2026-09-27-profiles-design.md
git commit -m "feat: Social.Person, the one read model of a person; people/0, own_person/0, Format.person_name/1"
```

---

### Task 3: Activity rows carry `author :: Person`

**Files:**
- Modify: `lib/media_centaur/activities.ex:67` (type), `:214-267` (`list_activities/0`, `friend_activity_for/1`), `:320-335` (`get_row/1`), `:413-417` (`activity_row/3`)
- Test: `test/media_centaur/activities/activities_test.exs`, `test/media_centaur/activities/sync_test.exs:50`

- [ ] **Step 1: Rewrite the row assertions**

In `test/media_centaur/activities/activities_test.exs`, add `alias MediaCentaur.Social.Person` to the aliases, then apply these replacements. Every pattern on the left appears in an `assert … =` and becomes the pattern on the right:

| Today | Becomes |
|---|---|
| `nickname: nil, own?: true` | `author: %Person{own?: true}` |
| `nickname: "Sample Friend", own?: false` | `author: %Person{name_override: "Sample Friend", own?: false}` |
| `nickname: "Sample Friend"` (alone, line 238) | `author: %Person{name_override: "Sample Friend"}` |
| `nickname: "Sam", own?: false` (line 636) | `author: %Person{name_override: "Sam", own?: false}` |
| `own?: true` alone (line 125) | `author: %Person{own?: true}` |

Rename the test at line 206 to `"a friend's activity carries the friend as its author"` and the one at 230 to `"accepts a friend's verified event, attributes it to the friend, broadcasts"`.

Add to the `describe "get_row/1 …"` block:

```elixir
    test "a removed friend's activity keeps its row but has no author; the lists drop it" do
      {:ok, _} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, rec} = Activities.ingest(friend_event(title(), "theirs", 1_700_000_000))
      :ok = Social.remove_friend(@friend_pubkey)

      assert %{activity: %Activity{id: id}, author: nil} = Activities.get_row(rec.id)
      assert id == rec.id
      assert Activities.list_activities() == []
      await_supervised_tasks()
    end
```

In `test/media_centaur/activities/sync_test.exs:50` replace `nickname: "Sample Friend"` with `author: %Person{name_override: "Sample Friend"}` and add `alias MediaCentaur.Social.Person`.

- [ ] **Step 2: Run red**

Run: `~/scripts/agents/agent-mix test test/media_centaur/activities/activities_test.exs test/media_centaur/activities/sync_test.exs`
Expected: FAIL on every row-shape assertion.

- [ ] **Step 3: The rows**

In `lib/media_centaur/activities.ex`:

Add `alias MediaCentaur.Social.Person`.

Replace the type at line 67:

```elixir
  @type activity_row :: %{activity: Activity.t(), author: Person.t() | nil}
```

Replace `list_activities/0` and its `@doc`:

```elixir
  @doc """
  Every activity by a person this reader knows, newest first, each with
  its author as the reader sees them (`Social.people/0`, ADR-074). A row
  whose author is neither the identity nor on the roster is left out: a
  former friend's activity is kept in the table and shown nowhere.
  Before an identity exists nothing stored can be ours.
  """
  @spec list_activities() :: [activity_row()]
  def list_activities do
    people = Social.people()

    Activity
    |> live()
    |> order_by(desc: :acted_at)
    |> Repo.all()
    |> Enum.filter(&is_map_key(people, &1.author_pubkey))
    |> Enum.map(&activity_row(&1, people))
  end
```

Replace `friend_activity_for/1`'s body (keep the `@doc`, but change its second sentence to "every kind a current friend has broadcast for the title (review, watched, listing) plus this identity's own reviews, each row with its author"):

```elixir
  def friend_activity_for(refs) when is_list(refs) do
    people = Social.people()
    tmdb_ids = refs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    wanted = MapSet.new(refs)

    Activity
    |> live()
    |> where([a], a.tmdb_id in ^tmdb_ids)
    |> order_by(desc: :acted_at)
    |> Repo.all()
    |> Enum.filter(fn activity ->
      MapSet.member?(wanted, {activity.tmdb_id, activity.media_type}) and
        pennant_author?(Map.get(people, activity.author_pubkey), activity.kind)
    end)
    |> Enum.group_by(&{&1.tmdb_id, &1.media_type}, &activity_row(&1, people))
  end
```

Replace `get_row/1`'s `@doc` first sentence with "One live activity by id as the rows carry it, `%{activity, author}`, the author nil for a person no longer known, or nil for an unknown, malformed or withdrawn id." and its body's row line:

```elixir
      activity_row(activity, Social.people())
```

Replace the two `activity_row/3` clauses with:

```elixir
  defp activity_row(%Activity{} = activity, people),
    do: %{activity: activity, author: Map.get(people, activity.author_pubkey)}

  # A pennant names a friend for any act, and the reader for a review alone.
  defp pennant_author?(nil, _kind), do: false
  defp pennant_author?(%Person{own?: true}, kind), do: kind == :review
  defp pennant_author?(%Person{}, _kind), do: true
```

Remove the now-unused `me = Identity.pubkey()` lines from those functions. `Identity` stays aliased for `publish_own/3`.

- [ ] **Step 4: Run green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/activities/activities_test.exs test/media_centaur/activities/sync_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/activities.ex test/media_centaur/activities/activities_test.exs test/media_centaur/activities/sync_test.exs
git commit -m "refactor: activity rows carry their author as a Person; unknown authors make no row"
```

---

### Task 4: The row fixture builds Persons

**Files:**
- Modify: `test/support/discovery_rows.ex`

- [ ] **Step 1: Rewrite the fixture**

Replace the file with:

```elixir
defmodule MediaCentaur.DiscoveryRows do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Enriched activity rows in the shape `DiscoveryLive` assigns — the
  `Activities.activity_row/0` (`activity` and its `author`, a
  `Social.Person`) plus the page's joins (poster and library owner,
  watchlist membership, acquisition state) — for the pure projection
  and component tests. `person/2` and `own_person/1` build the authors.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title

  @friend_pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @own_pubkey "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"

  @doc "A friend as the reader sees them, under the reader's name for them."
  @spec person(String.t(), keyword()) :: Person.t()
  def person(name, opts \\ []) when is_binary(name) do
    %Person{
      pubkey: Keyword.get(opts, :pubkey, @friend_pubkey),
      name_override: name,
      avatar_url: Keyword.get(opts, :avatar_url),
      own?: false,
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }
  end

  @doc "The reader as a person."
  @spec own_person(String.t()) :: Person.t()
  def own_person(pubkey \\ @own_pubkey), do: %Person{pubkey: pubkey, own?: true}

  @doc """
  One enriched row. `author:` is the Person (a friend named Sample
  Friend unless given); the activity's `author_pubkey` follows the
  author unless the activity overrides set one.
  """
  def activity_row(overrides \\ %{}) do
    activity = Map.get(overrides, :activity, %{})
    author = Map.get(overrides, :author, person("Sample Friend"))
    tmdb_id = Map.get(activity, :tmdb_id, 777)
    media_type = Map.get(activity, :media_type, :movie)

    title =
      Title.new!(%{
        tmdb_id: tmdb_id,
        media_type: media_type,
        name: Map.get(activity, :name, "Sample Movie #{tmdb_id}")
      })

    %{
      activity:
        struct!(
          Activity,
          Map.merge(
            %{
              id:
                Map.get(
                  activity,
                  :id,
                  "activity-#{tmdb_id}-#{Map.get(activity, :kind, :review)}"
                ),
              kind: :review,
              sentiment: :like,
              text: nil,
              episode: nil,
              tmdb_id: tmdb_id,
              media_type: media_type,
              title: title,
              author_pubkey: author.pubkey,
              acted_at: ~U[2026-09-01 12:00:00Z]
            },
            Map.delete(activity, :name)
          )
        ),
      author: author,
      poster_url: Map.get(overrides, :poster_url),
      library_owner_id: Map.get(overrides, :library_owner_id),
      rung: Map.get(overrides, :rung),
      acquisition_state: Map.get(overrides, :acquisition_state)
    }
  end
end
```

- [ ] **Step 2: Compile it**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/person_test.exs`
Expected: test support compiles and the test passes. Projection tests stay red until Tasks 6 and 9.

- [ ] **Step 3: Commit**

```bash
git add test/support/discovery_rows.ex
git commit -m "test: the enriched-row fixture builds a Person author"
```

---

### Task 5: The identity tile takes a Person

**Files:**
- Modify: `lib/media_centaur_web/components/discovery/identity_tile.ex`
- Modify: `storybook/discovery/identity_tile.story.exs`
- Test: `test/media_centaur_web/components/discovery/identity_tile_test.exs`

Two marks in this phase: the avatar when the Person has one, else the letter of the words the reader sees. The third mark, the person glyph for a nameless friend, arrives with phase 2, when a name can be missing.

- [ ] **Step 1: Rewrite the test**

```elixir
defmodule MediaCentaurWeb.Components.Discovery.IdentityTileTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.DiscoveryRows, only: [person: 1, person: 2, own_person: 0]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias MediaCentaurWeb.Components.Discovery.IdentityTile

  defp render(attrs), do: LazyHTML.from_fragment(render_component(&IdentityTile.identity_tile/1, attrs))

  defp tile(html), do: LazyHTML.query(html, "[data-component='identity-tile']")

  defp letter(html), do: html |> tile() |> LazyHTML.text() |> String.trim()

  defp mark(html), do: html |> tile() |> LazyHTML.attribute("data-mark")

  test "a friend is the monogram: the reader's name for them, first letter uppercased, hidden from assistive tech" do
    html = render(person: person("cleo"), size: 40)

    assert letter(html) == "C"
    assert mark(html) == ["letter"]
    assert html |> tile() |> LazyHTML.attribute("aria-hidden") == ["true"]
    assert html |> tile() |> LazyHTML.attribute("data-own") == []
    assert html |> tile() |> LazyHTML.attribute("data-size") == ["40"]
  end

  test "an own tile says so and takes the letter of You" do
    html = render(person: own_person(), size: 48)

    assert html |> LazyHTML.query("[data-component='identity-tile'][data-own]") |> Enum.count() == 1
    assert letter(html) == "Y"
  end

  test "an avatar replaces the letter and paints eagerly" do
    html = render(person: person("Ada", avatar_url: "/images/storybook/sample-poster.jpg"), size: 48)
    img = LazyHTML.query(html, "[data-component='identity-tile'] img")

    assert mark(html) == ["avatar"]
    assert LazyHTML.attribute(img, "src") == ["/images/storybook/sample-poster.jpg"]
    assert LazyHTML.attribute(img, "loading") == ["eager"]
    assert letter(html) == ""
  end

  test "the size is one of the two the surfaces render" do
    assert_raise ArgumentError, ~r/40 or 48/, fn -> render(person: person("Cleo"), size: 56) end
  end
end
```

- [ ] **Step 2: Run red**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/identity_tile_test.exs`
Expected: FAIL, the component has no `person` attr.

- [ ] **Step 3: Rewrite the component**

```elixir
defmodule MediaCentaurWeb.Components.Discovery.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046, UIDR-047): a circle
  carrying the **avatar** when the person has one the reader shows, else
  the **letter**, the first of the words the reader sees for them
  (`Format.person_name/1`, so the reader's own tile takes the Y of You).
  UIDR-047's third mark, the person glyph for a friend with no name at
  all, lands with the profiles campaign's phase 2, when a name can be
  missing. The reader's own tile is filled with the button primary and a
  white letter, so an own row is found without reading; an avatar inside
  a 2px primary ring says the same. Two sizes: 40 on a Feed row and the
  rail's person card, 48 on the Friends page's. `aria-hidden`: the name
  is read from the surface's text, the tile is its redundant channel.

  `data-mark` names the mark drawn, for tests and probes. No avatar
  exists yet (phase 3); the attr is the space the design leaves for one.
  """

  use Phoenix.Component

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person

  attr :person, Person, required: true, doc: "as the reader sees them"
  attr :size, :integer, required: true, values: [40, 48]

  def identity_tile(assigns) do
    assigns =
      assign(assigns,
        size_classes: size_classes(assigns.size),
        mark: mark(assigns.person),
        own?: assigns.person.own?
      )

    ~H"""
    <span
      class={[
        "relative grid shrink-0 place-items-center overflow-hidden rounded-full leading-none",
        @size_classes,
        @mark == :letter && !@own? &&
          "bg-primary/20 font-semibold text-primary ring-1 ring-inset ring-primary/25 shadow-[0_2px_8px_oklch(0%_0_0/0.35)]",
        @mark == :letter && @own? &&
          "bg-primary font-bold text-primary-content shadow-[0_2px_8px_oklch(0%_0_0/0.4)]",
        @mark == :avatar && !@own? && "ring-1 ring-inset ring-base-content/20",
        @mark == :avatar && @own? && "ring-2 ring-primary"
      ]}
      data-component="identity-tile"
      data-size={@size}
      data-own={@own?}
      data-mark={@mark}
      aria-hidden="true"
    >
      <img
        :if={@mark == :avatar}
        src={@person.avatar_url}
        alt=""
        class="size-full object-cover"
        loading="eager"
        decoding="sync"
      />
      {if @mark == :letter, do: Format.monogram(Format.person_name(@person))}
    </span>
    """
  end

  defp mark(%Person{avatar_url: url}) when is_binary(url), do: :avatar
  defp mark(%Person{}), do: :letter

  # The states are disjoint branches rather than a base plus overrides:
  # class precedence is stylesheet order, not template order. The size
  # is checked here as well as by `values:` because a template's check is
  # compile-time only — a dynamic `size={@n}` would otherwise render an
  # unsized circle.
  defp size_classes(40), do: "size-10 text-base"
  defp size_classes(48), do: "size-12 text-[19px]"

  defp size_classes(size),
    do: raise(ArgumentError, "identity_tile size must be 40 or 48, got: #{inspect(size)}")
end
```

- [ ] **Step 4: Run green**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/identity_tile_test.exs`
Expected: PASS, 4 tests.

- [ ] **Step 5: Rewrite the story**

Replace `storybook/discovery/identity_tile.story.exs` with:

```elixir
defmodule MediaCentaurWeb.Storybook.Discovery.IdentityTile do
  @moduledoc """
  The app's one drawing of a person (UIDR-046, UIDR-047): the letter and
  the avatar, for a friend and for the reader's own filled tile, at the
  two sizes the surfaces render: 40 on a Feed row and the rail's person
  card, 48 on the Friends page's. No profile event carries an avatar yet
  (phase 3); the avatar variations pin the space the design leaves for
  one. The person glyph joins with phase 2.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Social.Person

  def function, do: &MediaCentaurWeb.Components.Discovery.IdentityTile.identity_tile/1
  def render_source, do: :function

  @friend "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @me "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
  @photo "/images/storybook/sample-poster.jpg"

  def variations do
    [
      %VariationGroup{
        id: :row_40,
        description: "A Feed row and the rail's person card: 40px, the letter at 16",
        variations: states(40)
      },
      %VariationGroup{
        id: :page_48,
        description: "The Friends page's card: 48px, the letter at 19",
        variations: states(48)
      }
    ]
  end

  defp states(size) do
    [
      %Variation{
        id: :letter,
        description: "A friend: the first letter of your name for them on a primary tint",
        attributes: %{person: friend("Cleo"), size: size}
      },
      %Variation{
        id: :avatar,
        description: "A friend with an avatar: the picture inside a neutral ring",
        attributes: %{person: %{friend("Ada") | avatar_url: @photo}, size: size}
      },
      %Variation{
        id: :own,
        description: "The reader: filled with the button primary, the Y of You in white",
        attributes: %{person: %Person{pubkey: @me, own?: true}, size: size}
      },
      %Variation{
        id: :own_avatar,
        description: "The reader with an avatar: the picture inside a 2px primary ring",
        attributes: %{person: %Person{pubkey: @me, own?: true, avatar_url: @photo}, size: size}
      }
    ]
  end

  defp friend(name),
    do: %Person{pubkey: @friend, name_override: name, own?: false, short_npub: "npub1lyy9…8z4h", added_on: ~D[2026-08-30]}
end
```

- [ ] **Step 6: Render the story**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: the identity tile story compiles and renders. Other stories fail until Tasks 6, 7 and 9; read only the identity tile lines.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web/components/discovery/identity_tile.ex storybook/discovery/identity_tile.story.exs test/media_centaur_web/components/discovery/identity_tile_test.exs
git commit -m "refactor: the identity tile takes a Person and draws the avatar or the letter of the words the reader sees"
```

---

### Task 6: The Feed reads a Person

**Files:**
- Modify: `lib/media_centaur_web/components/discovery/feed_entry.ex`
- Modify: `lib/media_centaur_web/live/discovery_live/feed_entries.ex:124-155`
- Modify: `lib/media_centaur_web/components/discovery/feed_row.ex:50-70`, `:88-90`, `:159`, `:182-183`
- Modify: `storybook/discovery/feed_row.story.exs`
- Test: `test/media_centaur_web/components/discovery/feed_row_test.exs`, `test/media_centaur_web/live/discovery_live/feed_entries_test.exs`

- [ ] **Step 1: Rewrite the feed row test's fixture and own-row test**

In `test/media_centaur_web/components/discovery/feed_row_test.exs`:

Add `import MediaCentaur.DiscoveryRows, only: [person: 1, own_person: 0]`. In `entry/1`, replace the two lines `author: "Sample Friend",` and `own?: false,` with `author: person("Sample Friend"),`. Replace the last test with:

```elixir
  test "the author is the identity tile at 40: filled on an own row, with the second-person verb and no Ignore" do
    own = render(%{author: own_person()})

    assert own
           |> LazyHTML.query("[data-component='identity-tile'][data-size='40'][data-own]")
           |> Enum.count() == 1

    assert own |> LazyHTML.query("[data-component='feed-row'][data-own]") |> Enum.count() == 1
    who = own |> LazyHTML.query("[data-role='who']") |> LazyHTML.text() |> String.replace(~r/\s+/, " ")
    assert who =~ "You want to watch"
    assert Enum.empty?(LazyHTML.query(own, "#feed-row-a-ignore"))

    friend = render(%{})

    assert friend
           |> LazyHTML.query("[data-component='identity-tile'][data-size='40']:not([data-own])")
           |> Enum.count() == 1

    assert friend |> LazyHTML.query("#feed-row-a-ignore") |> Enum.count() == 1
  end
```

- [ ] **Step 2: Rewrite the projection test's fixtures**

In `test/media_centaur_web/live/discovery_live/feed_entries_test.exs`:

Change the import to `import MediaCentaur.DiscoveryRows, only: [activity_row: 1, person: 1, own_person: 0]`, add `alias MediaCentaur.Social.Person`, and replace the `row/3` helper with:

```elixir
  defp row(name, attrs, overrides \\ %{}) do
    activity_row(Map.merge(%{author: person(name), activity: attrs}, overrides))
  end

  defp own(attrs, overrides \\ %{}) do
    activity_row(Map.merge(%{author: own_person(), activity: attrs}, overrides))
  end
```

Then, through the file: every `row(nil, X, %{own?: true})` becomes `own(X)`; every `row(nil, X, %{own?: true, k: v})` becomes `own(X, %{k: v})`; every bare `own?: true` inside an `activity_row(%{…})` call becomes `author: own_person()`. Delete the former-friend row `row(nil, %{tmdb_id: 5, kind: :listing, id: "gone"}, %{own?: false})` from the first test and rename that test to `"keeps every author's reviews and listings; drops watched and ignored"` (a former friend never reaches the page now; Activities keeps rows for known people only). In the assertions near line 190: `author: "Nick", own?: false,` becomes `author: %Person{name_override: "Nick", own?: false},`; `author: "You", own?: true,` becomes `author: %Person{own?: true},`; `author: "Cleo", own?: false,` becomes `author: %Person{name_override: "Cleo", own?: false},`.

- [ ] **Step 3: Run red**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/feed_row_test.exs test/media_centaur_web/live/discovery_live/feed_entries_test.exs`
Expected: FAIL (`FeedEntry` has no Person author; `own?` is still a key).

- [ ] **Step 4: The struct**

In `lib/media_centaur_web/components/discovery/feed_entry.ex`: add `alias MediaCentaur.Social.Person`; remove `:own?,` from `defstruct` and `own?: boolean(),` from the type; change `author: String.t(),` to `author: Person.t(),`. In the moduledoc replace the sentence beginning "`author` is the display name" through "(never on an own row)." with: "`author` is the person as the reader sees them (`Social.Person`); its `own?` decides the verb's subject and whether Ignore renders (never on an own row), and `Format.person_name/1` gives its words." Write the trailing clause as "A view-model: every fact here was resolved by the host".

- [ ] **Step 5: The projection**

In `lib/media_centaur_web/live/discovery_live/feed_entries.ex`: add `alias MediaCentaur.Social.Person`. Replace the entry rule and scope clauses:

```elixir
  # The entry rule: a review or a listing on a title not ignored. Who
  # wrote it is the scope's question; that the author is known is
  # Activities' (a former friend's rows never reach the page).
  defp entry?(%{activity: activity, rung: rung}), do: activity.kind in @kinds and rung != :ignored

  defp in_scope?(_row, :everyone), do: true
  defp in_scope?(%{author: %Person{own?: own?}}, :friends), do: not own?
  defp in_scope?(%{author: %Person{own?: own?}}, :you), do: own?
```

In `entry/2` replace the two lines `author: if(row.own?, do: "You", else: row.nickname),` and `own?: row.own?,` with `author: row.author,`. In the moduledoc, change "Watched actions, a former friend's actions and any title at the Ignored rung make no row for any author; the activities themselves stay for the Friends tab and the pennants." to "Watched actions and any title at the Ignored rung make no row for any author; a former friend's rows never reach the page (Activities keeps rows for known people only)."

- [ ] **Step 6: The row**

In `lib/media_centaur_web/components/discovery/feed_row.ex`: add `alias MediaCentaur.Format` and `alias MediaCentaur.Social.Person`. Then:

- `data-own={@entry.own?}` becomes `data-own={@entry.author.own?}`
- `<IdentityTile.identity_tile name={@entry.author} own?={@entry.own?} size={40} />` becomes `<IdentityTile.identity_tile person={@entry.author} size={40} />`
- `<span class="font-medium text-base-content/95">{@entry.author}</span>` becomes `<span class="font-medium text-base-content/95">{Format.person_name(@entry.author)}</span>`
- `:if={not @entry.own?}` on the Ignore button becomes `:if={not @entry.author.own?}`
- the two `subject/1` clauses become:

```elixir
  defp subject(%FeedEntry{author: %Person{own?: true}}), do: :you
  defp subject(%FeedEntry{}), do: :friend
```

- [ ] **Step 7: Run green**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/discovery/feed_row_test.exs test/media_centaur_web/live/discovery_live/feed_entries_test.exs`
Expected: PASS.

- [ ] **Step 8: The story**

In `storybook/discovery/feed_row.story.exs`: add `alias MediaCentaur.Social.Person`. In `entry/2` replace `author: "Sample Friend",` and `own?: false,` with `author: friend(),`. Add two helpers:

```elixir
  defp friend,
    do: %Person{
      pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
      name_override: "Sample Friend",
      own?: false,
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }

  defp you, do: %Person{pubkey: "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5", own?: true}
```

Every variation override `author: "You", own?: true` becomes `author: you()`.

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_render_test.exs`
Expected: the feed row story renders (read its lines; others stay red until Tasks 7 and 9).

- [ ] **Step 9: Commit**

```bash
git add lib/media_centaur_web/components/discovery/feed_entry.ex lib/media_centaur_web/live/discovery_live/feed_entries.ex lib/media_centaur_web/components/discovery/feed_row.ex storybook/discovery/feed_row.story.exs test/media_centaur_web/components/discovery/feed_row_test.exs test/media_centaur_web/live/discovery_live/feed_entries_test.exs
git commit -m "refactor: the Feed's entry carries its author as a Person; the row reads the words through person_name"
```

---

### Task 7: The pennant flies people

**Files:**
- Modify: `lib/media_centaur_web/components/title/pennant.ex:60-110`
- Modify: `storybook/title/pennants.story.exs:27-38`, `storybook/title/title_row.story.exs:35-46`, `storybook/acquisition/media_results.story.exs:57-68`, `storybook/composites/cinematic_shell.story.exs:59-70`, `storybook/detail_panel/detail_panel.story.exs:688-701`
- Test: `test/media_centaur_web/components/title/pennant_test.exs`

- [ ] **Step 1: Rewrite the pennant test's fixtures and name assertions**

In `test/media_centaur_web/components/title/pennant_test.exs`: add `import MediaCentaur.DiscoveryRows, only: [person: 1, own_person: 0]` and `alias MediaCentaur.Format`. Replace the two fixture helpers:

```elixir
  defp friend(name, attrs),
    do: %{activity: build_activity(Map.new(attrs)), author: person(name)}

  defp own(sentiment),
    do: %{activity: build_activity(%{sentiment: sentiment}), author: own_person()}
```

Where a test asserts on `names`, read them through the people: `%{flag: :like, names: ["Sam", "Alex", "You"]}` becomes a two-step assert:

```elixir
      assert %{flag: :like, people: people} = like
      assert Enum.map(people, &Format.person_name/1) == ["Sam", "Alex", "You"]
```

(bind the pennant to `like` from the mast list first; the existing test destructures the list, so name each element). For `label/1` and `tooltip/1` tests, build the pennant with people instead of strings:

```elixir
      assert Pennant.label(%{flag: :like, people: [person("Nick"), person("Sam"), own_person()]}) == "Nick +2"
      assert Pennant.tooltip(%{flag: :like, people: [own_person()]}) == "You like this"
      assert Pennant.tooltip(%{flag: :dislike, people: [person("Nick"), own_person()]}) == "Nick and you dislike this"
```

Apply the same change to every remaining `names: [...]` in that file: each string becomes `person("<name>")`, each `"You"` becomes `own_person()`.

- [ ] **Step 2: Run red**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/pennant_test.exs`
Expected: FAIL.

- [ ] **Step 3: Rewrite the pure half**

In `lib/media_centaur_web/components/title/pennant.ex`: add `alias MediaCentaur.Format` and `alias MediaCentaur.Social.Person`. Find the `@type pennant` (or add one above `mast/1`) and make it:

```elixir
  @type pennant :: %{flag: Flag.flag(), people: [Person.t()]}
```

Replace `mast/1` (and the misnamed `@spec pennants(...)` above it), `label/1`, `tooltip/1` and the `verb/2` clauses with:

```elixir
  @doc """
  The mast for one title's activity rows: one pennant per flag in mast
  order, the people in the rows' order (newest first) with the reader
  last.
  """
  @spec mast([%{activity: Activity.t(), author: Person.t()}]) :: [pennant()]
  def mast(rows) do
    by_flag = Enum.group_by(rows, &Flag.flag(&1.activity))

    for flag <- Flag.mast_order(), group = Map.get(by_flag, flag, []), group != [] do
      {own, friends} = Enum.split_with(group, & &1.author.own?)
      %{flag: flag, people: Enum.map(friends ++ own, & &1.author)}
    end
  end

  @max_named 2

  @doc ~s(Up to two names, then a count: "Nick, Sam", "Nick +2".)
  @spec label(pennant()) :: String.t()
  def label(%{people: people}) do
    names = Enum.map(people, &Format.person_name/1)

    if length(names) <= @max_named,
      do: Enum.join(names, ", "),
      else: "#{hd(names)} +#{length(names) - 1}"
  end

  @doc ~s(The whole statement: "Nick loves this", "Nick dislikes this", "Nick, Sam and you like this", "Nick reviewed this", "Nick wants to watch this".)
  @spec tooltip(pennant()) :: String.t()
  def tooltip(%{flag: flag, people: people}) do
    plural? = length(people) > 1
    subjects = Enum.map(people, &subject_word(&1, plural?))

    subject =
      case subjects do
        [one] -> one
        many -> Enum.join(Enum.drop(many, -1), ", ") <> " and " <> List.last(many)
      end

    "#{subject} #{verb(flag, people)} this"
  end

  # The reader is "you" mid-sentence and "You" alone.
  defp subject_word(%Person{own?: true}, true), do: "you"
  defp subject_word(person, _plural?), do: Format.person_name(person)

  defp verb(:love, [%Person{own?: false}]), do: "loves"
  defp verb(:like, [%Person{own?: false}]), do: "likes"
  defp verb(:dislike, [%Person{own?: false}]), do: "dislikes"
  defp verb(:listing, [_one]), do: "wants to watch"
  defp verb(:love, _plural_or_you), do: "love"
  defp verb(:like, _plural_or_you), do: "like"
  defp verb(:dislike, _plural_or_you), do: "dislike"
  defp verb(:review, _any), do: "reviewed"
  defp verb(:watched, _any), do: "watched"
  defp verb(:listing, _plural), do: "want to watch"
```

In the moduledoc, "A pennant carries up to two nicknames and then a count" becomes "A pennant carries up to two names and then a count".

- [ ] **Step 4: Run green**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/pennant_test.exs`
Expected: PASS.

- [ ] **Step 5: The five stories that build rows**

Each of these stories has a row-building helper carrying `nickname: nickname, own?: is_nil(nickname)` (or `own?: false`). In each, add `alias MediaCentaur.Social.Person` and replace those two map keys with `author: author(nickname)`, then add this helper to the story module:

```elixir
  # nil is the reader; a string is a friend under your name for them.
  defp author(nil), do: %Person{pubkey: "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5", own?: true}

  defp author(name),
    do: %Person{
      pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
      name_override: name,
      own?: false,
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }
```

Files and helpers: `storybook/title/pennants.story.exs` (`row/3`), `storybook/title/title_row.story.exs` (`review/2`), `storybook/acquisition/media_results.story.exs` (`review/3`), `storybook/composites/cinematic_shell.story.exs` (`activity_row/3`; every call there passes a name, so give it only the second clause), `storybook/detail_panel/detail_panel.story.exs` (`act/6`).

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_render_test.exs`
Expected: these five render; only the person card story stays red until Task 9.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/title/pennant.ex test/media_centaur_web/components/title/pennant_test.exs storybook/title/pennants.story.exs storybook/title/title_row.story.exs storybook/acquisition/media_results.story.exs storybook/composites/cinematic_shell.story.exs storybook/detail_panel/detail_panel.story.exs
git commit -m "refactor: the pennant flies people, its words from person_name; the second person keys on own?"
```

---

### Task 8: The detail panel's words and the review modal's preview

**Files:**
- Modify: `lib/media_centaur_web/components/detail_panel.ex:580`, `:850-853`
- Modify: `lib/media_centaur_web/live/review_modal.ex:125-127`
- Modify: `lib/media_centaur_web/live/title_detail_host.ex:893` (`activity_delete` matches `author: %Person{own?: true}`), `:998` (`provenance/1`: the reader's own activity carries none; any other author, nil included, does)
- Test: `test/media_centaur_web/components/title/logic_test.exs:86`

(The two host clauses were found by the Task 8 quality review; the plan had missed them. Sweep with `grep -rn "own?: true\|own?: false\|nickname" lib | grep -v "Person{"` after this task: only `people.ex` (Task 9) may remain.)

- [ ] **Step 1: Fix the logic test's row**

In `test/media_centaur_web/components/title/logic_test.exs`, add `import MediaCentaur.DiscoveryRows, only: [person: 1]` and change line 86 to:

```elixir
      row = %{activity: build_activity(%{text: "Watch it."}), author: person("Sample Friend")}
```

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/logic_test.exs`
Expected: PASS (the detail struct types `activity` as `Activities.activity_row()`, which already changed).

- [ ] **Step 2: The panel**

In `lib/media_centaur_web/components/detail_panel.ex`, add `alias MediaCentaur.Format` (if absent) and `alias MediaCentaur.Social.Person`. Replace line 580:

```elixir
  defp own_activity(%TitleDetail{activity: %{activity: activity, author: %Person{own?: true}}}), do: activity
```

Replace the `note_words/1` head clause and its comment:

```elixir
  # The words under the hero: the activity's text attributed to its
  # author when a friend wrote it (the reader's own words stand
  # unattributed), else the person's own watchlist note.
  defp note_words(%TitleDetail{activity: %{activity: %{text: text}, author: author}})
       when is_binary(text) and text != "",
       do: %{sender: sender(author), text: text}
```

and add below `note_words/1`:

```elixir
  defp sender(%Person{own?: false} = person), do: Format.person_name(person)
  defp sender(_own_or_unknown), do: nil
```

- [ ] **Step 3: The preview**

In `lib/media_centaur_web/live/review_modal.ex`, add `alias MediaCentaur.Social` and replace `preview/1`:

```elixir
  # The choice shows the pennant the friend will see, worded as the
  # choice itself rather than as the sender's name: the reader's own
  # pennant, with or without an identity yet.
  defp preview(sentiment),
    do: %{activity: %Activity{kind: :review, sentiment: sentiment}, author: Social.own_person()}
```

- [ ] **Step 4: Compile and run the nearest tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/components/title/logic_test.exs`
Expected: PASS, no warnings. The LiveView tests in Task 10 cover the modal.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/detail_panel.ex lib/media_centaur_web/live/review_modal.ex test/media_centaur_web/components/title/logic_test.exs
git commit -m "refactor: the detail's attributed words and the review preview read the row's author"
```

---

### Task 9: `Act` moves, `People` builds cards, `PersonCard` takes a person and their acts

**Files:**
- Create: `lib/media_centaur_web/components/discovery/act.ex`
- Delete: `lib/media_centaur_web/components/discovery/person.ex`
- Modify: `lib/media_centaur_web/live/discovery_live/people.ex`
- Modify: `lib/media_centaur_web/components/discovery/person_card.ex`
- Modify: `storybook/discovery/person_card.story.exs`
- Test: `test/media_centaur_web/live/discovery_live/people_test.exs`, `test/media_centaur_web/components/discovery/person_card_test.exs`

- [ ] **Step 1: Rewrite the People test**

Replace the top of `test/media_centaur_web/live/discovery_live/people_test.exs` (through `own/1`) with:

```elixir
defmodule MediaCentaurWeb.DiscoveryLive.PeopleTest do
  use MediaCentaur.Case, async: true

  import MediaCentaur.DiscoveryRows

  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.DiscoveryLive.People
  alias MediaCentaurWeb.DiscoveryLive.People.Card

  @now ~U[2026-09-03 12:00:00Z]
  @me "0101010101010101010101010101010101010101010101010101010101010101"
  @bob "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
  @alice "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
  @cleo "e493dbf1c10d80f3581e4904930b1404cc6c13900ee0758474fa94abe8c4cd13"

  defp friend(pubkey, name, added),
    do: %Person{pubkey: pubkey, name_override: name, own?: false, short_npub: "npub1…", added_on: added}

  # The known people, with or without the reader.
  defp people(me?) do
    friends = [
      friend(@alice, "Alice", ~D[2026-08-30]),
      friend(@bob, "Bob", ~D[2026-08-30]),
      friend(@cleo, "Cleo", ~D[2026-09-02])
    ]

    base = Map.new(friends, &{&1.pubkey, &1})
    if me?, do: Map.put(base, @me, own_person(@me)), else: base
  end

  defp activity(name, pubkey, attrs) do
    activity_row(%{author: person(name, pubkey: pubkey), activity: Map.put(attrs, :author_pubkey, pubkey)})
  end

  defp own(attrs) do
    activity_row(%{author: own_person(@me), activity: Map.put(attrs, :author_pubkey, @me)})
  end

  defp names(cards), do: Enum.map(cards, &Format.person_name(&1.person))
```

Then through the file:

- every `People.build(rows, friends(), me: true, now: @now)` becomes `People.build(rows, people(true), now: @now)`; every `me: false` form becomes `people(false)`; a call with a one-friend list `[friend(@cleo, "Cleo", …)]` becomes `%{@cleo => friend(@cleo, "Cleo", ~D[2026-09-02])}`.
- `assert Enum.map(people, & &1.name) == ["You", "Bob", "Alice", "Cleo"]` becomes `assert names(people) == ["You", "Bob", "Alice", "Cleo"]`.
- `assert [%Person{own?: true, id: "person-you", pubkey: nil} | _friends] = people` becomes `assert [%Card{person: %Person{own?: true, pubkey: @me}} | _friends] = people`.
- `assert [%Person{name: "Alice"} | _rest] = People.build(...)` becomes `assert ["Alice" | _rest] = names(People.build([], people(false), now: @now))`.
- Where tests index cards by name (`by_name["Cleo"]` and the like), build the index with `Map.new(cards, &{Format.person_name(&1.person), &1})` and read acts as `card.acts`.
- The test "a former friend's activity has no card, and a quiet friend has no acts" becomes:

```elixir
  test "a quiet friend is a card with no acts" do
    people = People.build([], %{@cleo => friend(@cleo, "Cleo", ~D[2026-09-02])}, now: @now)

    assert [%Card{person: %Person{name_override: "Cleo"}, acts: []}] = people
  end
```

- The rail test becomes:

```elixir
  test "rail/1 takes You and the seven most recent, and counts who the cap hid" do
    people =
      for index <- 1..12,
          do: %Card{person: %Person{pubkey: String.pad_leading("#{index}", 64, "0"), name_override: "Friend #{index}"}}

    you = %Card{person: own_person(@me)}

    assert %{cards: shown, hidden: 5} = People.rail([you | people])
    assert length(shown) == 8
    assert hd(shown).person.own?

    assert %{cards: [^you], hidden: 0} = People.rail([you])
  end
```

- [ ] **Step 2: Rewrite the PersonCard test**

In `test/media_centaur_web/components/discovery/person_card_test.exs`:

Replace the aliases with:

```elixir
  import MediaCentaur.DiscoveryRows, only: [person: 1, own_person: 0]

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Discovery.Act
  alias MediaCentaurWeb.Components.Discovery.Act.Entry
  alias MediaCentaurWeb.Components.Discovery.PersonCard
```

Replace `friend_with_acts/1`, `you_with_acts/0` and `quiet_friend/0` with:

```elixir
  defp friend, do: person("Sample Friend")

  defp acts_of(count \\ 3) do
    [
      act(7, [:love, :watched], id: "r7", gold: [:love]),
      act(9, [:watched], id: "w9a"),
      act(11, [:listing], id: "l11")
    ] ++
      for index <- 4..count//1, do: act(100 + index, [:watched], id: "w#{index}")
  end

  defp you_acts, do: [act(7, [:love], id: "r7")]
```

Then every `render(person: friend_with_acts(N), …)` becomes `render(person: friend(), acts: acts_of(N), …)` (and `friend_with_acts()` → `acts: acts_of()`); every `render(person: you_with_acts(), …)` becomes `render(person: own_person(), acts: you_acts(), …)`; every `render(person: quiet_friend(), …)` becomes `render(person: friend(), acts: [], …)`; the `bare` case becomes `render(person: friend(), acts: [act(7, [:watched], id: "w7", poster_url: nil)], width: :rail)`.

Add two tests:

```elixir
  test "the opened foot carries your name for the friend, ready to change" do
    html = render(person: person("Nick"), acts: [], width: :page, opened?: true)
    input = LazyHTML.query(html, "footer [data-role='name-form'] input[name='name']")

    assert LazyHTML.attribute(input, "value") == ["Nick"]
    assert html |> LazyHTML.query("footer [data-role='name-form']") |> LazyHTML.attribute("phx-submit") == ["set_friend_name"]
    assert html |> LazyHTML.query("footer input[name='pubkey']") |> LazyHTML.attribute("value") == [person("Nick").pubkey]
  end

  test "dom_id/1 is person-you for the reader and the key's first eight hex digits for a friend" do
    assert PersonCard.dom_id(own_person()) == "person-you"
    assert PersonCard.dom_id(friend()) == "person-f9308a01"
    assert render(person: friend(), acts: [], width: :rail) |> LazyHTML.query("#person-f9308a01") |> Enum.count() == 1
  end
```

- [ ] **Step 3: Run red**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live/people_test.exs test/media_centaur_web/components/discovery/person_card_test.exs`
Expected: FAIL (`Act` and `Card` undefined).

- [ ] **Step 4: Move `Act`**

Create `lib/media_centaur_web/components/discovery/act.ex` with the `Entry` and `Act` modules moved out of `person.ex`, nested as `Act.Entry`:

```elixir
defmodule MediaCentaurWeb.Components.Discovery.Act do
  @moduledoc """
  One title a person acted on (UIDR-046): what the person card's strip
  shows for it — the poster under its flags, in mast order, `gold`
  naming the flags at the grade — and every activity behind it, newest
  first. The newest activity's id, time, ago and episode are the act's:
  the press opens it, the ago is its. Built by `DiscoveryLive.People`,
  rendered by `PersonCard`; a view-model, the card decides nothing.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Flag

  defmodule Entry do
    @moduledoc "One activity behind an act: what the opened card's row and the title modal need."

    defstruct [:activity_id, :kind, :flag, :episode, :acted_at]

    @type t :: %__MODULE__{
            activity_id: String.t(),
            kind: Activity.kind(),
            flag: Flag.flag(),
            episode: Episode.t() | nil,
            acted_at: DateTime.t()
          }
  end

  defstruct [
    :ref,
    :title,
    :poster_url,
    :activity_id,
    :acted_at,
    :ago,
    :episode,
    flags: [],
    gold: [],
    entries: []
  ]

  @type t :: %__MODULE__{
          ref: {integer(), Title.media_type()},
          title: Title.t(),
          poster_url: String.t() | nil,
          activity_id: String.t(),
          acted_at: DateTime.t(),
          ago: String.t(),
          episode: Episode.t() | nil,
          flags: [Flag.flag()],
          gold: [Flag.flag()],
          entries: [Entry.t()]
        }
end
```

Delete `lib/media_centaur_web/components/discovery/person.ex`:

```bash
git rm lib/media_centaur_web/components/discovery/person.ex
```

- [ ] **Step 5: Rewrite `People`**

Replace `lib/media_centaur_web/live/discovery_live/people.ex` with:

```elixir
defmodule MediaCentaurWeb.DiscoveryLive.People do
  @moduledoc """
  Folds the page's enriched activity rows into person cards (ADR-030,
  ADR-074, UIDR-046): one `Card` — a `Social.Person` and their acts —
  for the reader first when the known people include them, then friends
  by their latest act of any kind, then friends with no acts by name.
  The rows carry known people only (Activities drops a former friend's),
  so every row lands on a card.

  A person's acts are one per title, newest first; each flies every act
  on that title in mast order, and a flag is **gold** when two or more
  friends did that act on that title — counted once over the rows this
  fold already holds, one count per friend per title and flag, the
  reader's own acts not counting. `rail/1` is the Feed's rail: the first
  eight of that order and how many the cap hid.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Discovery.Act
  alias MediaCentaurWeb.Components.Discovery.Act.Entry
  alias MediaCentaurWeb.Components.Title.Flag

  defmodule Card do
    @moduledoc """
    One person card's content: the person as the reader sees them and
    their acts, newest first. `PersonCard` renders it from the two
    attrs; `PersonCard.dom_id/1` names it.
    """

    defstruct [:person, acts: []]

    @type t :: %__MODULE__{person: Person.t(), acts: [Act.t()]}
  end

  @grade 2
  @rail_cap 8

  @doc """
  The cards for `people` (the `Social.people/0` map) from the enriched
  activity rows. `now` anchors each act's relative time.
  """
  @spec build([map()], %{optional(String.t()) => Person.t()}, now: DateTime.t()) :: [Card.t()]
  def build(rows, people, opts) do
    now = Keyword.fetch!(opts, :now)
    by_author = Enum.group_by(rows, & &1.activity.author_pubkey)
    gold = rows |> Enum.reject(& &1.author.own?) |> gold_flags()
    {me, friends} = people |> Map.values() |> Enum.split_with(& &1.own?)

    you = Enum.map(me, &card(&1, Map.get(by_author, &1.pubkey, []), now, gold))

    friends
    |> Enum.map(&card(&1, Map.get(by_author, &1.pubkey, []), now, gold))
    |> Enum.sort_by(&sort_key/1)
    |> then(&(you ++ &1))
  end

  @doc "The Feed's rail: the first eight cards in `build/3`'s order, and how many the cap hid."
  @spec rail([Card.t()]) :: %{cards: [Card.t()], hidden: non_neg_integer()}
  def rail(cards) do
    {shown, hidden} = Enum.split(cards, @rail_cap)
    %{cards: shown, hidden: length(hidden)}
  end

  # The (title, flag) pairs at the grade: each friend once per pair
  # however many rows they have on it.
  defp gold_flags(rows) do
    rows
    |> Enum.map(&{ref(&1), Flag.flag(&1.activity), &1.activity.author_pubkey})
    |> Enum.uniq()
    |> Enum.frequencies_by(fn {ref, flag, _author} -> {ref, flag} end)
    |> Enum.filter(fn {_pair, count} -> count >= @grade end)
    |> MapSet.new(fn {pair, _count} -> pair end)
  end

  # Latest act first; the quiet ones after, by name.
  defp sort_key(%Card{acts: [], person: person}), do: {1, 0, Format.person_name(person)}

  defp sort_key(%Card{acts: [%Act{acted_at: at} | _rest], person: person}),
    do: {0, -DateTime.to_unix(at), Format.person_name(person)}

  defp card(%Person{} = person, rows, now, gold) do
    sorted = Enum.sort_by(rows, & &1.activity.acted_at, {:desc, DateTime})
    %Card{person: person, acts: acts(sorted, gold, now)}
  end

  # One act per title in the order the titles first appear — newest
  # first, since the rows are sorted — with every row behind it.
  defp acts(sorted, gold, now) do
    by_ref = Enum.group_by(sorted, &ref/1)

    sorted
    |> Enum.map(&ref/1)
    |> Enum.uniq()
    |> Enum.map(&act(&1, Map.fetch!(by_ref, &1), gold, now))
  end

  defp act(ref, [%{activity: %Activity{} = newest} = first | _rest] = rows, gold, now) do
    flags = rows |> Enum.map(&Flag.flag(&1.activity)) |> Flag.sort_by_mast()

    %Act{
      ref: ref,
      title: newest.title,
      poster_url: first.poster_url,
      activity_id: newest.id,
      acted_at: newest.acted_at,
      ago: Format.relative_ago(newest.acted_at, now: now, sub_minute: :just_now),
      episode: newest.episode,
      flags: flags,
      gold: Enum.filter(flags, &MapSet.member?(gold, {ref, &1})),
      entries: Enum.map(rows, &entry/1)
    }
  end

  defp entry(%{activity: %Activity{} = activity}) do
    %Entry{
      activity_id: activity.id,
      kind: activity.kind,
      flag: Flag.flag(activity),
      episode: activity.episode,
      acted_at: activity.acted_at
    }
  end

  defp ref(%{activity: %Activity{tmdb_id: tmdb_id, media_type: media_type}}), do: {tmdb_id, media_type}
end
```

`short_npub/1` is gone from here; `Social.short_npub/1` (Task 2) is its home.

- [ ] **Step 6: Rewrite `PersonCard`**

Replace `lib/media_centaur_web/components/discovery/person_card.ex` with:

```elixir
defmodule MediaCentaurWeb.Components.Discovery.PersonCard do
  @moduledoc """
  One person as their latest acts (UIDR-046, UIDR-047), on the Feed's
  rail and the Friends page from one function at two widths. The head
  is the identity tile and the name the reader sees (`Format.person_name/1`)
  — no clock: the card says what a person did, the Feed says when; under
  it the **acts strip**: one poster per title acted on, newest first,
  each under its **act glyphs** — a 36px strip on the card's ground with
  the glyphs for what the person did centred as a group in mast order
  (the opinion, the eye, the bookmark), one act in the middle, two as a
  pair. A flag at the grade is gold; the rest are matte. A person with
  no acts is a tile and a name; the card says nothing about what a
  person withholds, and the You card is the reader's acts like anyone's,
  the filled own tile its only mark.

  The rail's card (`width: :rail`) is a row in the rail's list — no
  ground of its own, a hairline between cards — showing three acts; its
  press navigates to the person on the Friends page. The page's card
  (`:page`) is a card in the Friends grid on the inset tone, showing
  five acts; its press opens the card in place (`opened?`, the host's
  set): every act, one row per poster in `ActivityWords`' sentence with
  the act's flags after the title, then a friend's foot — the reader's
  name for the friend, ready to change, the key, the added date, Remove
  friend. A poster's press opens the title modal speaking for the newest
  act on it.

  Pure rendering of a `Social.Person` and their `Act`s. Every poster, row
  and Remove friend is a nav item that bubbles `open_title` with the
  title's ref *and* the activity, or `remove_friend`; the name form
  submits `set_friend_name` with the key and the name, and swallows its
  clicks (`phx-click={%JS{}}`, the modal panel's idiom) so typing in it
  does not press the card; `open_person` and `toggle_person` are the
  card's own presses. The root gets no nav wiring until the hardening
  pass.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1, icon: 1]
  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Discovery.Act
  alias MediaCentaurWeb.Components.Discovery.IdentityTile
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.DiscoveryLive.ActivityWords
  alias MediaCentaurWeb.TitleRef
  alias Phoenix.LiveView.JS

  @cap %{rail: 3, page: 5}

  attr :person, Person, required: true, doc: "the person as the reader sees them"
  attr :acts, :list, required: true, doc: "the person's `Act`s, newest first; `[]` for a quiet person"
  attr :width, :atom, required: true, values: [:rail, :page]
  attr :opened?, :boolean, default: false, doc: "the page card grown in place; the host keeps the set"
  attr :landed?, :boolean, default: false, doc: "the card the address names takes focus on mount"

  def person_card(assigns) do
    assigns =
      assign(assigns,
        id: dom_id(assigns.person),
        name: Format.person_name(assigns.person),
        shown: shown(assigns.acts, assigns.width, assigns.opened?),
        subject: subject(assigns.person),
        page?: assigns.width == :page
      )

    ~H"""
    <section
      id={@id}
      role="button"
      tabindex="-1"
      class={["person-card", @page? && "person-card-page", @opened? && "person-card-opened"]}
      data-component="person-card"
      data-width={@width}
      data-own={@person.own?}
      data-opened={@opened?}
      phx-click={if @page?, do: "toggle_person", else: "open_person"}
      phx-value-id={@id}
      phx-mounted={@landed? && JS.focus()}
    >
      <header class="flex items-center gap-3">
        <IdentityTile.identity_tile person={@person} size={tile_size(@width)} />
        <h2
          class={[
            "min-w-0 flex-1 truncate font-semibold",
            if(@page?, do: "text-xl leading-8", else: "text-lg leading-7")
          ]}
          data-role="name"
        >
          {@name}
        </h2>
      </header>

      <div
        :if={@acts != []}
        class={["acts-strip", if(@page?, do: "mt-4", else: "mt-2 pl-13")]}
        data-role="acts"
      >
        <button
          :for={act <- @shown}
          id={"#{@id}-act-#{TitleRef.param(act.ref)}"}
          type="button"
          class="act"
          title={@name <> " " <> sentence(act, @subject)}
          phx-click="open_title"
          phx-value-ref={TitleRef.param(act.ref)}
          phx-value-activity={act.activity_id}
          data-entity-id={TitleRef.param(act.ref)}
          data-flags={Enum.join(act.flags, " ")}
          data-nav-item
          tabindex="0"
        >
          <span class="act-slots" aria-hidden="true">
            <span
              :for={flag <- act.flags}
              class={["act-glyph", flag in act.gold && "act-glyph-gold"]}
              data-flag={flag}
            >
              <.icon name={Flag.glyph(flag, :solid)} class="act-icon" />
            </span>
          </span>
          <img
            :if={act.poster_url}
            src={act_poster_src(act.poster_url, @width)}
            alt={act.title.name}
            loading="eager"
            decoding="sync"
          />
          <span :if={!act.poster_url} class="act-empty text-sm leading-tight text-base-content/65">
            {act.title.name}
          </span>
        </button>
      </div>

      <div :if={@opened?} class="mt-5 space-y-1" data-role="act-rows">
        <button
          :for={act <- @acts}
          id={"#{@id}-#{act.activity_id}"}
          type="button"
          class="flex w-full cursor-pointer items-baseline gap-3 rounded-md px-2 py-1 text-left text-base leading-6 hover:bg-base-content/5"
          data-role="act-row"
          phx-click="open_title"
          phx-value-ref={TitleRef.param(act.ref)}
          phx-value-activity={act.activity_id}
          data-entity-id={TitleRef.param(act.ref)}
          data-nav-item
          tabindex="0"
        >
          <span class="min-w-0 flex-1 truncate text-base-content/80">
            {ActivityWords.verb_phrase(newest(act).kind, act.episode, @subject)}
            <span class="font-medium text-base-content/95">{act.title.name}</span>
            <span :for={flag <- act.flags} class="ml-1 inline-block align-middle" data-flag={flag}>
              <.icon name={Flag.glyph(flag, :solid)} class="size-4 text-base-content/80" />
            </span>
          </span>
          <span class="shrink-0 text-sm text-base-content/65">{act.ago}</span>
        </button>
      </div>

      <footer
        :if={@opened? and not @person.own?}
        class="mt-5 space-y-3 border-t border-base-content/10 pt-4"
      >
        <form
          id={"#{@id}-name-form"}
          class="flex items-center gap-2"
          phx-submit="set_friend_name"
          phx-click={%JS{}}
          data-role="name-form"
        >
          <input type="hidden" name="pubkey" value={@person.pubkey} />
          <input
            type="text"
            name="name"
            value={@person.name_override}
            class="library-filter basis-48 grow-0 shrink-0"
            autocomplete="off"
            aria-label="Your name for this friend"
          />
          <.button type="submit" variant="neutral" size="sm">Rename</.button>
        </form>
        <div class="flex items-center justify-between">
          <span class="text-sm text-base-content/65">
            <code>{@person.short_npub}</code> · added {Calendar.strftime(@person.added_on, "%b %-d")}
          </span>
          <.button
            variant="dismiss"
            size="sm"
            phx-click="remove_friend"
            phx-value-pubkey={@person.pubkey}
            data-nav-item
            tabindex="0"
          >
            Remove friend
          </.button>
        </div>
      </footer>
    </section>
    """
  end

  @doc """
  The card's DOM id: `person-you` for the reader, else `person-` and the
  key's first eight hex digits. The host's opened set and the address's
  `person=` speak it.
  """
  @spec dom_id(Person.t()) :: String.t()
  def dom_id(%Person{own?: true}), do: "person-you"
  def dom_id(%Person{pubkey: pubkey}), do: "person-" <> String.slice(pubkey, 0, 8)

  @doc "The poster derivative for the width it paints at: 96 CSS px on the rail, 130 on the page, ×2 for a 4K panel."
  @spec act_poster_src(String.t(), :rail | :page) :: String.t()
  def act_poster_src(url, :rail), do: sized_image_url(url, 240)
  def act_poster_src(url, :page), do: sized_image_url(url, 320)

  defp shown(acts, _width, true), do: acts
  defp shown(acts, width, false), do: Enum.take(acts, @cap[width])

  defp tile_size(:rail), do: 40
  defp tile_size(:page), do: 48

  defp subject(%Person{own?: true}), do: :you
  defp subject(%Person{}), do: :friend

  defp newest(%Act{entries: [entry | _rest]}), do: entry

  defp sentence(%Act{} = act, subject),
    do: ActivityWords.sentence(newest(act).kind, act.episode, act.title.name, subject)
end
```

If the formatter reflows the `<span>` holding `·`, MC0034 loses its same-line exemption; keep that span's content on one line as it was.

- [ ] **Step 7: Run green**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live/people_test.exs test/media_centaur_web/components/discovery/person_card_test.exs`
Expected: PASS.

- [ ] **Step 8: The story**

In `storybook/discovery/person_card.story.exs`: replace the three `Person`/`Act`/`Entry` aliases with

```elixir
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Discovery.Act
  alias MediaCentaurWeb.Components.Discovery.Act.Entry
```

Replace `friend/1` and `you/1` with:

```elixir
  defp friend do
    %Person{
      pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
      name_override: "Sample Friend",
      own?: false,
      short_npub: "npub1lyy9…8z4h",
      added_on: ~D[2026-08-30]
    }
  end

  defp you, do: %Person{pubkey: "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5", own?: true}
```

In every variation, `person: friend(ACTS)` becomes `person: friend(), acts: ACTS` and `person: you(ACTS)` becomes `person: you(), acts: ACTS`. For example `:rail_friend` becomes:

```elixir
      %Variation{
        id: :rail_friend,
        description: "The rail's card: three acts; the second flies love and watched as a centred pair",
        attributes: %{person: friend(), acts: three_acts(), width: :rail},
        template: @rail
      },
```

Update the `:page_opened` description to end "the foot with your name for them, the key, the date and Remove friend".

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS, every story.

- [ ] **Step 9: Commit**

```bash
git add lib/media_centaur_web/components/discovery/act.ex lib/media_centaur_web/live/discovery_live/people.ex lib/media_centaur_web/components/discovery/person_card.ex storybook/discovery/person_card.story.exs test/media_centaur_web/live/discovery_live/people_test.exs test/media_centaur_web/components/discovery/person_card_test.exs
git commit -m "refactor: the person card takes a Person and their acts; the web Person struct is retired; the foot renames a friend"
```

---

### Task 10: The Discovery LiveView and the add-friend form

**Files:**
- Modify: `lib/media_centaur_web/live/discovery_live.ex:50-60`, `:155`, `:235-242`, `:372-375`, `:425-460`, `:515-545`, `:760-768`, `:840-856`, the `tabs/4` helper and its call
- Modify: `lib/media_centaur_web/live/discovery_live/add_friend_block.ex`
- Test: `test/media_centaur_web/live/discovery_live_test.exs:180-262`

The LiveView keeps the people map alone: the friend count and the feed's readiness derive from it, so the roster is not held twice.

- [ ] **Step 1: Rewrite the two friend-tab tests and add the rename test**

In `test/media_centaur_web/live/discovery_live_test.exs`, replace the test "adds a friend by npub + name, shows their card, and removes" and the test "refuses a bad key, your own key, and a blank name with flashes" with:

```elixir
    test "adds a friend by npub and name, shows their card, renames from the foot, and removes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      npub = Keys.to_npub(@friend_pubkey)

      view
      |> form("#add-friend-form", %{"key" => npub, "name" => "Sample Friend"})
      |> render_submit()

      assert has_element?(view, friend_card() <> " h2", "Sample Friend")
      refute has_element?(view, friend_card(), "Nothing shared yet")
      refute has_element?(view, friend_card() <> " [data-role='acts']")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active .badge", "1")
      assert [%{name_override: "Sample Friend"}] = Social.list_friends()

      # The foot is behind the card's press: your name for them, and the key.
      view |> element(friend_card()) |> render_click()
      assert has_element?(view, friend_card() <> " footer", Social.short_npub(@friend_pubkey))

      view |> form(friend_card() <> " [data-role='name-form']", %{"name" => "Nick"}) |> render_submit()
      assert has_element?(view, friend_card() <> " h2", "Nick")
      assert has_element?(view, friend_card() <> " [data-role='name-form'] input[name='name'][value='Nick']")
      assert [%{name_override: "Nick"}] = Social.list_friends()

      view |> form(friend_card() <> " [data-role='name-form']", %{"name" => "  "}) |> render_submit()
      assert render(view) =~ "Give your friend a name"
      assert has_element?(view, friend_card() <> " h2", "Nick")

      view |> element(friend_card() <> " button", "Remove friend") |> render_click()
      refute has_element?(view, friend_card())
      assert Social.list_friends() == []
    end

    test "refuses a bad key, your own key, and a blank name with flashes", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live(conn, "/discovery/friends")

      view |> form("#add-friend-form", %{"key" => "npub1nope", "name" => "X"}) |> render_submit()
      assert render(view) =~ "That is not a valid public key"

      view
      |> form("#add-friend-form", %{"key" => Identity.npub(), "name" => "Me"})
      |> render_submit()

      assert render(view) =~ "That is your own key"

      view
      |> form("#add-friend-form", %{"key" => Keys.to_npub(@friend_pubkey), "name" => " "})
      |> render_submit()

      assert render(view) =~ "Give your friend a name"
      assert Social.list_friends() == []
    end
```

Elsewhere in the file: `People.short_npub(` becomes `Social.short_npub(` (line 209 in the old test; check for others), and if `People` is then unused, drop its alias.

- [ ] **Step 2: Run red**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs`
Expected: FAIL (the page still renders `person.id`, the form posts `nickname`).

- [ ] **Step 3: The LiveView**

In `lib/media_centaur_web/live/discovery_live.ex`:

Replace the `add_friend` handler (line 235):

```elixir
  def handle_event("add_friend", %{"key" => key, "name" => name}, socket) do
    case Social.add_friend(key, name) do
      {:ok, _friend} -> {:noreply, socket |> load_people() |> load_activities()}
      {:error, :own_key} -> {:noreply, put_flash(socket, :error, "That is your own key")}
      {:error, :name_required} -> {:noreply, put_flash(socket, :error, "Give your friend a name")}
      {:error, _invalid} -> {:noreply, put_flash(socket, :error, "That is not a valid public key")}
    end
  end

  # The opened card's foot: the reader's name for the friend.
  def handle_event("set_friend_name", %{"pubkey" => pubkey, "name" => name}, socket) do
    case Social.set_name_override(pubkey, name) do
      {:ok, _friend} -> {:noreply, socket |> load_people() |> load_activities()}
      {:error, :name_required} -> {:noreply, put_flash(socket, :error, "Give your friend a name")}
      {:error, :not_a_friend} -> {:noreply, put_flash(socket, :error, "That friend is no longer on your list")}
    end
  end
```

Replace every other `load_friends()` call in the module with `load_people()` (the `remove_friend` handler at line 246, the roster `handle_info` at line 374, mount at line 155).

Replace the roster `handle_info` (line 373):

```elixir
  def handle_info({tag, _event}, socket)
      when tag in [:friend_added, :friend_removed, :friend_changed, :identity_changed] do
    {:noreply, socket |> load_people() |> load_activities()}
  end
```

(If a `handle_info({:identity_changed, _}, …)` clause already exists further down, delete it in favour of this one.)

Replace `load_friends/1` (line 543):

```elixir
  # The known people (`Social.people/0`), the reader included when an
  # identity exists: the cards are built from the map, the tab's count
  # and the feed's readiness are derived from it. The roster is held once.
  defp load_people(socket) do
    people = Social.people()

    assign(socket,
      people_by_pubkey: people,
      friend_count: Enum.count(people, fn {_pubkey, person} -> not person.own? end)
    )
  end
```

In `load_activities/1`, `feed_ready?: Social.list_relays() != [] and Social.list_friends() != []` becomes `feed_ready?: Social.list_relays() != [] and socket.assigns.friend_count > 0` (mount calls `load_people` before `load_activities`, and every other caller keeps that order).

In `project/1`, replace the `People.build(...)` call:

```elixir
    people = People.build(socket.assigns.activities, socket.assigns.people_by_pubkey, now: now)
```

and remove the now-unused `alias MediaCentaur.Social.Identity` if the compiler reports it.

`tabs/4`: its third parameter becomes `friend_count` and the Friends tab's `count: length(friends)` becomes `count: friend_count`; at its call site pass `@friend_count` where `@friends` was.

In the Friends grid (line 760):

```heex
                  <PersonCard.person_card
                    :for={card <- @people}
                    person={card.person}
                    acts={card.acts}
                    width={:page}
                    opened?={MapSet.member?(@opened_people, PersonCard.dom_id(card.person))}
                    landed?={PersonCard.dom_id(card.person) == @landed_person}
                  />
```

In the rail component (line 840): its `attr :friends, :list, required: true, doc: "the roster, for the count"` becomes `attr :friend_count, :integer, required: true, doc: "for All N friends"`; `:if={@rail.people != []}` becomes `:if={@rail.cards != []}`; the card line becomes:

```heex
      <PersonCard.person_card :for={card <- @rail.cards} person={card.person} acts={card.acts} width={:rail} />
```

and `All {length(@friends)} friends` becomes `All {@friend_count} friends`. At the rail's call site, `friends={@friends}` becomes `friend_count={@friend_count}`.

Replace the moduledoc sentence at lines 56–59 ("A row added from a friend's action carries a bare `activity_id`, and this page turns it into `from <nickname>` … the join neither context may make.") with: "A row added from a friend's action carries a bare `activity_id`; the friend's name reaches the page through the pennants (`Activities.friend_activity_for/1`, whose rows carry their author as a `Social.Person`)."

In the comment above `load_activities/1` ("Activities owns the record and the nickname"), write "Activities owns the record and its author".

- [ ] **Step 4: The add-friend form**

In `lib/media_centaur_web/live/discovery_live/add_friend_block.ex`, the second input's `name="nickname"` becomes `name="name"`. Nothing else changes: the name is still required and still only the reader's.

- [ ] **Step 5: Run the LiveView tests green**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/discovery_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Look at it in the running app**

The dev daily driver has reloaded the new code; no migration was needed. Open a friend's card and rename them:

Run: `~/scripts/agents/page-shot --url http://localhost:2160/discovery/friends --viewport 1920x1080 --wait-ms 3000` and Read the PNG. Expected: the reader's card first, then friends, each under the reader's name for them.

Then verify the swallowed click with `chromium-probe`: open a friend's card by clicking it, click inside the name input, and confirm the card stays opened (`[data-component='person-card'][data-opened]` still present). If it closes, the `phx-click={%JS{}}` on the form did not swallow the press; move it onto the `<footer>` instead and re-check.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur_web/live/discovery_live.ex lib/media_centaur_web/live/discovery_live/add_friend_block.ex test/media_centaur_web/live/discovery_live_test.exs
git commit -m "feat: rename a friend from the card's foot; the page holds the people map once"
```

---

### Task 11: The whole suite and `precommit`

**Files:** none new.

- [ ] **Step 1: Run the suite**

Run: `~/scripts/agents/agent-mix test` (foreground, timeout 600000)
Expected: PASS. Any remaining failure is a reader of the old row shape (`nickname`, `own?`, `People.short_npub`, `Discovery.Person`) this plan missed; fix it in the module that owns it and add the file to this task's commit. `Social.add_friend/2` kept its arity and its required name, so the tests under `incoming_live_test`, `library_live_test`, `status_live_test` and `page_smoke_test` that add a friend need no change.

- [ ] **Step 2: Run precommit**

Run: `~/scripts/agents/agent-mix precommit` (foreground, timeout 600000)
Expected: format, credo, boundaries, deps.audit, sobelow and test all pass with zero warnings. Likely reports and their fixes: an unused alias (remove it); a Boundary complaint that `MediaCentaurWeb` reaches `MediaCentaur.Social.Person` without it in `exports` (Task 2 added it; run `~/scripts/agents/agent-mix compile --force` once, since a new module in `exports` needs a forced compile); `mix_unused` flagging a function no longer called (delete it).

- [ ] **Step 3: Commit any fixes**

```bash
git add -A lib test storybook
git commit -m "chore: precommit clean after the Person read model"
```

(Skip if nothing changed.)

---

### Task 12: Docs, the topics table, the campaign, the wiki

**Files:**
- Modify: `docs/social.md` (Contexts table, Web layer, PubSub topics)
- Modify: `lib/media_centaur/topics.ex:61` (the `social:updates` row)
- Modify: `campaigns/profiles.md`
- Modify: `../media-centaur.wiki/Social.md` (Friends)

- [ ] **Step 1: `docs/social.md`**

Contexts table, the `MediaCentaur.Social` row's "Owns" cell: append "and `Person`, a key as the reader sees it, built by `Social.people/0` (ADR-074)."

Web layer, the Friends bullet: replace "`DiscoveryLive.People` folds the list into one `Components.Discovery.Person` per friend and one for You (when an identity exists)" with "`DiscoveryLive.People` folds the list into one `People.Card` (a `Social.Person` and their acts) per known person, the reader first when an identity exists". Replace "`Components.Discovery.PersonCard` renders it at two widths" with "`Components.Discovery.PersonCard` renders a person and their acts at two widths". At the end of that bullet append: "The opened card's foot carries the reader's name for the friend (`Social.set_name_override/2`), the key, the added date and Remove friend. `DiscoveryLive.AddFriendBlock` takes an npub and the name; re-adding a key changes nothing."

The "Activity rows" bullet under "The joins the contexts may not make": replace "returns the record plus the friend's nickname (`nil` for a former friend; `own?: true`, `nickname: nil` for this identity's own)" with "returns the record plus its `author`, a `Social.Person`, for authors the reader knows; a former friend's rows are left out". Replace the "Watchlist rows" bullet's "resolves it to a nickname through `Activities.get_many/1` → `Social.list_friends/0`" with "resolves it through `Activities.get_row/1`, whose `author` may be nil for a removed friend".

Add a paragraph after the Web layer's opening sentence: "A person is drawn from one read model everywhere, `Social.Person` (ADR-074): the reader's name for a friend, the avatar URL (nil until the profiles campaign's phase 3), and whether it is the reader's own; phase 2 adds the name the key published. `MediaCentaur.Format.person_name/1` gives the words ("You" or the name); `Components.Discovery.IdentityTile` draws the avatar or the letter (UIDR-047)."

PubSub table, `social:updates` row: add `{:friend_changed, _}` after `{:friend_added, _}`.

- [ ] **Step 2: `lib/media_centaur/topics.ex`**

In the moduledoc table's `social:updates` row, add `{:friend_changed, _}` after `{:friend_added, _}`.

- [ ] **Step 3: The campaign**

In `campaigns/profiles.md`: `last_updated: <today>`; Status: "Phase 1 (roster and Person) shipped on main <date>; phase 2 (the profile on the wire, opening with the `friends` rebuild and the optional name) next, social-relay v0.7.0 first."; Next steps: strike the phase 1 step and renumber.

- [ ] **Step 4: The wiki**

In `~/src/media-centaur/media-centaur.wiki/Social.md`, Friends section, the opened-card sentence: "Press a card to open it in place: every title as a row … then your name for the friend, which you can change (**Rename** saves it), the friend's key, when you added them, and **Remove friend**." Where the page says re-adding a friend renames them, if it does, replace it with: "Adding a friend you already have changes nothing; rename them from their card."

```sh
cd ~/src/media-centaur/media-centaur.wiki
git add -A
git commit -m "wiki: rename a friend from their card"
```

Do not push the wiki either until told.

- [ ] **Step 5: Commit the app docs**

```bash
git add docs/social.md lib/media_centaur/topics.ex campaigns/profiles.md
git commit -m "docs: Social.Person and FriendChanged in the social guide and the topics table; the profiles campaign at phase 2"
```

---

## Self-review against the spec (done at plan time)

Spec § Design → tasks: the Person read model (2, 3), the web reads a Person (5–10), roster API and events (1), the card's rename (9, 10), one name function (2). Moved to phase 2 by the unify pass, and recorded above: the rebuild, the optional name, Unnamed, the person glyph, `published_name`, `Person.name/1`, the placeholder. Moved to phase 3: `show_avatar`, `set_show_avatar/2`, the switch. Not in this phase by design: the wire, the relay, storage of profiles, RelaySync, Settings, the avatar upload, `ProfileUpdated`. Types used across tasks: `Social.Person` fields `pubkey`, `name_override`, `avatar_url`, `own?`, `short_npub`, `added_on`; `Social.people/0`, `own_person/0`, `short_npub/1`, `add_friend/2` (name required, `:name_required`), `set_name_override/2` (`:name_required`, `:not_a_friend`); `Events.FriendChanged`; `Format.person_name/1`; rows `%{activity, author}`; `Components.Discovery.Act`, `Act.Entry`; `People.Card` with `person`, `acts`; `People.build/3` taking the people map; `People.rail/1` returning `cards`; `PersonCard` attrs `person`, `acts`; `PersonCard.dom_id/1`; `IdentityTile` attrs `person`, `size`, `data-mark` in `letter`/`avatar`; LiveView assigns `people_by_pubkey`, `friend_count`; LiveView events `add_friend` (`key`, `name`) and `set_friend_name` (`pubkey`, `name`); DiscoveryRows `person/2`, `own_person/1`, `activity_row/1`.
