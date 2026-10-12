# Relay Follow Rule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A relay carries a per-reader follow rule — *Everyone on this relay* (members) or *Only people I add* (added) — so a friend group on its own relay sees one another without swapping keys, and the reader can hide anyone.

**Architecture:** `Social` owns three pieces of state: the rule on the relay row, one `contacts` row per key the reader has a view of (today's `friends` table, widened with `added_at` and `hidden`), and `relay_members`, the keys seen publishing on a members-rule relay. The sync loop subscribes without an author filter on a members-rule relay, notes each author before routing the event, and sweeps the relay's members once a read completes. Surfaces read everything through `Social.people/0` as today. The relay repository deletes a removed member's stored events so the group stops seeing them.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto + SQLite (`ecto_sqlite3`), Phoenix Storybook, ExUnit with `Nostr.FakeRelay`; Go + khatru in `../social-relay`.

**Spec:** `docs/superpowers/specs/2026-10-12-relay-follow-rule-design.md`.

**Conventions for every task:**
- Run mix through `~/scripts/agents/agent-mix` (never bare `mix`; the dev server shares the checkout).
- Every commit message ends with the trailer line `Claude-Session: https://claude.ai/code/session_01E4gsziNDHQDHxmNcs5ZE4b`.
- No real show titles in tests or docs. Use `Sample Movie`, `Sample Friend`, `Sample Member`.
- `MediaCentaur.Case` templates: context tests `use MediaCentaur.DataCase, async: false`; LiveView tests `use MediaCentaurWeb.ConnCase, async: false`.
- The final task runs `~/scripts/agents/agent-mix precommit`; fix everything it reports.

---

## File structure

| File | Responsibility |
|---|---|
| `priv/repo/migrations/20261012120000_relay_follow_rule.exs` | create | the schema change, one migration |
| `lib/media_centaur/social/relay.ex` | modify | `follow` field |
| `lib/media_centaur/social/contact.ex` | create (from `friend.ex`, deleted) | the reader's state about a key |
| `lib/media_centaur/social/relay_member.ex` | create | observed membership |
| `lib/media_centaur/social/events.ex` | modify | `RelayChanged`, `MembersChanged`, `ContactChanged` |
| `lib/media_centaur/social/person.ex` | modify | `friend?`, `hidden`, `member_of`, `member_hosts/1` |
| `lib/media_centaur/social.ex` | modify | rule, contacts, members, `followed_key?/1`, `people/0` |
| `lib/media_centaur/relay_sync.ex` | modify | per-relay filter, note, sweep |
| `lib/media_centaur/activities.ex` | modify | `followed_key?`, hidden filtered |
| `lib/media_centaur_web/components/settings.ex` | modify | `settings_select/1` extracted |
| `lib/media_centaur_web/live/settings_live/social_section.ex` | modify | rule select on the add form and each row |
| `lib/media_centaur_web/live/settings_live.ex` | modify | `add_relay` with rule, `set_relay_follow`, `:relay_changed` |
| `lib/media_centaur_web/components/social/person_card.ex` | modify | foot: provenance, Hide, Remove friend only for a friend |
| `lib/media_centaur_web/components/social/hidden_person_row.ex` | create | the hidden group's row |
| `lib/media_centaur_web/live/social_live/people.ex` | modify | hidden left out of cards; `hidden/1` |
| `lib/media_centaur_web/live/social_live.ex` | modify | `set_hidden`, tags, hidden group, copy |
| `storybook/settings/settings_select.story.exs`, `storybook/social/hidden_person_row.story.exs` | create | stories |
| `storybook/social/person_card.story.exs` | modify | friend/member fixtures |
| `test/support/nostr/fake_relay.ex` | modify | `replace_events/2` |
| `../social-relay/internal/relay/membership.go`, `management.go`, `relay.go` | modify | forget a removed member's events |
| docs: `docs/social.md`, `docs/GLOSSARY.md`, `lib/media_centaur/topics.ex`, wiki `Social.md`, `Settings-Reference.md`, `Hosting-a-Private-Relay.md`; relay `docs/protocol.md`, `docs/operating.md` | modify | |

---

### Task 1: Migration, schemas, events, boundary

**Files:**
- Create: `priv/repo/migrations/20261012120000_relay_follow_rule.exs`
- Create: `lib/media_centaur/social/contact.ex`
- Delete: `lib/media_centaur/social/friend.ex`
- Create: `lib/media_centaur/social/relay_member.ex`
- Modify: `lib/media_centaur/social/relay.ex`
- Modify: `lib/media_centaur/social/events.ex`
- Modify: `lib/media_centaur/social.ex` (aliases, boundary exports, `Friend` → `Contact` mechanically)
- Rename: `test/media_centaur/social/friend_test.exs` → `test/media_centaur/social/contacts_test.exs`

- [ ] **Step 1: Write the migration**

```elixir
defmodule MediaCentaur.Repo.Migrations.RelayFollowRule do
  @moduledoc """
  A relay carries its follow rule (`members` or `added`); the roster becomes
  `contacts`, one row per key the reader has a view of, with `added_at`
  (nil for a key followed only through a relay) and `hidden`;
  `relay_members` records the keys seen publishing on a members-rule relay.
  """
  use Ecto.Migration

  def change do
    alter table(:relays) do
      add :follow, :text, null: false, default: "added"
    end

    drop unique_index(:friends, [:pubkey])
    rename table(:friends), to: table(:contacts)

    alter table(:contacts) do
      add :added_at, :utc_datetime
      add :hidden, :boolean, null: false, default: false
    end

    create unique_index(:contacts, [:pubkey])
    execute "UPDATE contacts SET added_at = inserted_at", "UPDATE contacts SET added_at = NULL"

    create table(:relay_members, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :relay_id, references(:relays, type: :uuid, on_delete: :delete_all), null: false
      add :pubkey, :text, null: false
      add :seen_at, :utc_datetime_usec, null: false
    end

    create unique_index(:relay_members, [:relay_id, :pubkey])
    create index(:relay_members, [:pubkey])
  end
end
```

- [ ] **Step 2: Write `Social.Contact`** (replaces `Social.Friend`; `git mv lib/media_centaur/social/friend.ex lib/media_centaur/social/contact.ex` then overwrite)

```elixir
defmodule MediaCentaur.Social.Contact do
  @moduledoc """
  One public key the reader has a view of: the x-only key as lowercase hex
  and the reader's own state about it, none of it from the network.
  `added_at` is set when the reader added the key by hand — a **friend** —
  and nil for a key followed only because it publishes on a relay whose
  follow rule is members (`Social.RelayMember`). `name_override`
  (UIDR-047) is the reader's word for the person, masking the published
  name; blank is none. `show_avatar` is the reader's switch for the
  published picture, on by default. `hue_override` (UIDR-048) masks the
  published hue; nil is none. `hidden` keeps the person's activity off
  every surface but the Friends tab's hidden group.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "contacts" do
    field :pubkey, :string
    field :added_at, :utc_datetime
    field :name_override, :string
    field :show_avatar, :boolean, default: true
    field :hue_override, :integer
    field :hidden, :boolean, default: false

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for a contact row; the pubkey must already be lowercase hex."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(contact \\ %__MODULE__{}, attrs) do
    contact
    |> cast(attrs, [:pubkey, :added_at, :name_override, :show_avatar, :hue_override, :hidden])
    |> update_change(:name_override, &blank_to_nil/1)
    |> validate_required([:pubkey, :show_avatar, :hidden])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint(:pubkey)
  end

  @doc "Whether the reader added this key by hand."
  @spec friend?(t()) :: boolean()
  def friend?(%__MODULE__{added_at: added_at}), do: added_at != nil

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
```

- [ ] **Step 3: Write `Social.RelayMember`**

```elixir
defmodule MediaCentaur.Social.RelayMember do
  @moduledoc """
  One key seen publishing on a relay whose follow rule is members
  (`Social.Relay`): observed by the sync loop, never configured. `seen_at`
  is when the current connect last delivered an event by the key;
  `Social.sweep_members/2` drops the rows a connect did not refresh. The
  rows go with the relay (`on_delete: :delete_all`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.Social.Relay

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "relay_members" do
    belongs_to :relay, Relay, type: Ecto.UUID
    field :pubkey, :string
    field :seen_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for a membership row; the pubkey must already be lowercase hex."
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:relay_id, :pubkey, :seen_at])
    |> validate_required([:relay_id, :pubkey, :seen_at])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint([:relay_id, :pubkey])
  end
end
```

- [ ] **Step 4: Add the rule to `Social.Relay`**

In `lib/media_centaur/social/relay.ex` replace the moduledoc's first paragraph and the schema/changeset:

```elixir
  @moduledoc """
  One configured relay: a `ws://` or `wss://` URL, normalized (trimmed,
  lowercase scheme and host, no userinfo, path defaults to `/`), and the
  reader's **follow rule** for it: `:members` follows everyone who
  publishes on the relay (*Everyone on this relay*, for a friend group's own
  allowlist relay); `:added` follows only the keys the reader added (*Only
  people I add*, the default, for any larger or public relay).
  Connection state is runtime (`Social.Connections.status/0`), never
  stored, and neither is any sync position: every connect reads the relay
  from the start (`RelaySync`).
  """
```

```elixir
  schema "relays" do
    field :url, :string
    field :follow, Ecto.Enum, values: [:members, :added], default: :added

    timestamps()
  end

  @type t :: %__MODULE__{}
  @typedoc "Who the reader follows on a relay: everyone publishing on it, or only the keys they added."
  @type follow :: :members | :added

  @doc "Changeset for a relay row; normalizes the URL, then validates the normalized form."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(relay \\ %__MODULE__{}, attrs) do
    relay
    |> cast(attrs, [:url, :follow])
    |> update_change(:url, &normalize/1)
    |> validate_required([:url, :follow])
    |> validate_change(:url, fn :url, url ->
      if valid?(url), do: [], else: [url: "must start with wss:// or ws://"]
    end)
    |> unique_constraint(:url)
  end
```

- [ ] **Step 5: Events**

In `lib/media_centaur/social/events.ex`: rename `FriendChanged` to `ContactChanged` with moduledoc `"The reader's choices for a contact changed: the name override, the avatar switch, the hue override or hidden."`, tag `:contact_changed`; add after `RelayRemoved`:

```elixir
  defmodule RelayChanged do
    @moduledoc "A relay's follow rule changed."
    @enforce_keys [:url]
    defstruct [:url]
    @type t :: %__MODULE__{url: String.t()}
  end

  defmodule MembersChanged do
    @moduledoc "A members-rule relay's observed members changed: a key was seen on it for the first time, or a read ended without one."
    @enforce_keys [:url]
    defstruct [:url]
    @type t :: %__MODULE__{url: String.t()}
  end
```

Extend `@type t` and add:

```elixir
  def broadcast(%RelayChanged{} = event), do: publish({:relay_changed, event})
  def broadcast(%MembersChanged{} = event), do: publish({:members_changed, event})
  def broadcast(%ContactChanged{} = event), do: publish({:contact_changed, event})
```

(remove the `FriendChanged` clause.)

- [ ] **Step 6: Mechanical rename in `social.ex` and the boundary**

In `lib/media_centaur/social.ex`: exports become

```elixir
    exports: [
      Connections,
      Contact,
      Events,
      Events.ContactChanged,
      Events.FriendAdded,
      Events.FriendRemoved,
      Events.IdentityChanged,
      Events.MembersChanged,
      Events.ProfileUpdated,
      Events.RelayAdded,
      Events.RelayChanged,
      Events.RelayRemoved,
      Identity,
      Person,
      Profile,
      Profile.Translation,
      Relay,
      RelayMember
    ]
```

Replace `alias MediaCentaur.Social.Friend` with `alias MediaCentaur.Social.Contact` and `alias MediaCentaur.Social.RelayMember`; replace every `Friend` / `%Friend{}` with `Contact` / `%Contact{}`; every `Events.FriendChanged` with `Events.ContactChanged`. Behaviour changes come in Tasks 2–5; this step only compiles.

- [ ] **Step 7: Rename and adjust the existing test file**

`git mv test/media_centaur/social/friend_test.exs test/media_centaur/social/contacts_test.exs`; module `MediaCentaur.Social.ContactsTest`; alias `Contact` for `Friend`, `ContactChanged` for `FriendChanged`, `{:contact_changed, %ContactChanged{...}}` for every `{:friend_changed, ...}`; `Social.contact_by_pubkey/1` for `Social.friend_by_pubkey/1` here (line 78) and in `test/media_centaur_web/live/social_live_test.exs` (five sites, lines 234–265). Also in `lib/media_centaur_web/live/social_live.ex` change `@people_tags` to `[:friend_added, :friend_removed, :contact_changed, :identity_changed, :profile_updated]` (extended again in Task 11).

- [ ] **Step 8: Migrate and run the two context test files**

Run: `~/scripts/agents/agent-mix ecto.migrate && ~/scripts/agents/agent-mix test test/media_centaur/social/`
Expected: all pass (the renamed assertions, the relay tests).

- [ ] **Step 9: Commit**

```bash
git add -A priv/repo/migrations lib/media_centaur/social lib/media_centaur/social.ex lib/media_centaur_web/live/social_live.ex test/media_centaur/social
git commit -m "refactor(social): contacts, relay follow rule and relay members schemas"
```

---

### Task 2: Relay rule in `Social`

**Files:**
- Modify: `lib/media_centaur/social.ex`
- Test: `test/media_centaur/social/relay_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/media_centaur/social/relay_test.exs` (alias `MediaCentaur.Social.Events.RelayChanged`, `MediaCentaur.Social.Relay`):

```elixir
  describe "follow rule" do
    test "a relay is added under a rule, added by default; the same URL keeps its rule" do
      assert {:ok, %Relay{follow: :added}} = Social.add_relay("wss://relay.example")
      assert {:ok, %Relay{follow: :members}} = Social.add_relay("wss://group.example", :members)
      assert {:ok, %Relay{follow: :members}} = Social.add_relay("wss://group.example", :added)
      assert %Relay{follow: :members} = Social.get_relay("WSS://group.example/")
      assert Social.get_relay("wss://nowhere.example") == nil
    end

    test "set_follow/2 changes the rule and broadcasts once; the same rule again is silent; unknown is refused" do
      {:ok, _relay} = Social.add_relay("wss://relay.example")
      Social.subscribe()

      assert {:ok, %Relay{follow: :members}} = Social.set_follow("wss://relay.example", :members)
      assert_receive {:relay_changed, %RelayChanged{url: "wss://relay.example/"}}, 500

      assert {:ok, %Relay{follow: :members}} = Social.set_follow("wss://relay.example", :members)
      refute_receive {:relay_changed, _event}, 100

      assert {:error, :unknown_relay} = Social.set_follow("wss://nowhere.example", :members)
    end
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/relay_test.exs`
Expected: FAIL — `Social.add_relay/2`, `get_relay/1`, `set_follow/2` undefined.

- [ ] **Step 3: Implement**

In `lib/media_centaur/social.ex` replace `add_relay/1` and `insert_relay/2`, and add `get_relay/1` and `set_follow/2`:

```elixir
  @doc """
  Adds a relay URL under a follow rule (`Relay.follow/0`), added unless
  given. Idempotent on the normalized URL: an existing relay keeps its rule
  (`set_follow/2` changes it).
  """
  @spec add_relay(String.t(), Relay.follow()) :: {:ok, Relay.t()} | {:error, Ecto.Changeset.t()}
  def add_relay(url, follow \\ :added) when is_binary(url) and follow in [:members, :added] do
    normalized = Relay.normalize(url)

    case Repo.get_by(Relay, url: normalized) do
      %Relay{} = existing -> {:ok, existing}
      nil -> insert_relay(url, normalized, follow)
    end
  end

  @doc "One relay by URL (normalized first), or nil."
  @spec get_relay(String.t()) :: Relay.t() | nil
  def get_relay(url) when is_binary(url), do: Repo.get_by(Relay, url: Relay.normalize(url))

  @doc """
  Sets a relay's follow rule. Members → added forgets the relay's observed
  members: a key followed only through it stops being followed and its
  profile goes (`sweep_members/2` has the same rule). Broadcasts
  `RelayChanged` when it changed; the same rule again is silent.
  """
  @spec set_follow(String.t(), Relay.follow()) :: {:ok, Relay.t()} | {:error, :unknown_relay}
  def set_follow(url, follow) when is_binary(url) and follow in [:members, :added] do
    case get_relay(url) do
      nil ->
        {:error, :unknown_relay}

      %Relay{follow: ^follow} = relay ->
        {:ok, relay}

      relay ->
        relay = Repo.update!(Relay.changeset(relay, %{follow: follow}))
        if follow == :added, do: forget_members(relay)
        Events.broadcast(%Events.RelayChanged{url: relay.url})
        {:ok, relay}
    end
  end
```

```elixir
  defp insert_relay(url, normalized, follow) do
    case Repo.insert(Relay.changeset(%{url: url, follow: follow})) do
      {:ok, relay} ->
        Events.broadcast(%Events.RelayAdded{url: relay.url})
        {:ok, relay}

      {:error, changeset} ->
        # A concurrent insert of the same URL is the idempotent case, not a failure.
        if unique_violation?(changeset),
          do: {:ok, Repo.get_by!(Relay, url: normalized)},
          else: {:error, changeset}
    end
  end

  # Drops every membership row of a relay and prunes what the keys no
  # longer earn (Task 4 adds `prune_if_unfollowed/1`; until then this
  # deletes the rows only).
  defp forget_members(%Relay{id: relay_id}) do
    Repo.delete_all(from(member in RelayMember, where: member.relay_id == ^relay_id))
    :ok
  end
```

- [ ] **Step 4: Run to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/relay_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/social.ex test/media_centaur/social/relay_test.exs
git commit -m "feat(social): a relay carries its follow rule"
```

---

### Task 3: Contacts — promote, demote, hide, followed keys

**Files:**
- Modify: `lib/media_centaur/social.ex`
- Test: `test/media_centaur/social/contacts_test.exs`

- [ ] **Step 1: Write the failing tests**

Replace the `known_key?/1` describe in `contacts_test.exs` and add the rest (alias `MediaCentaur.Social.Events.ContactChanged`, `MediaCentaur.Social.Relay`, `MediaCentaur.Social.Profile.Translation, as: ProfileTranslation`, `MediaCentaur.Nostr.Event`, `MediaCentaur.Secret`):

```elixir
  @secret Secret.wrap(String.duplicate("0", 63) <> "3")

  defp profile_event(name),
    do:
      Event.sign(
        ProfileTranslation.to_event(%{name: name, avatar: nil, hue: nil}, @pubkey, 1_700_000_000),
        @secret
      )

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

      assert {:ok, %Contact{name_override: "Given"}} = Social.add_friend(@pubkey, "Given")
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
      other = String.duplicate("c", 64)
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
```

Also change the existing `refuses a key not on the roster` and similar assertions from `{:error, :not_a_friend}` to `{:error, :not_a_contact}`, and `remove_friend/1`'s existing test keeps passing: the roster is empty though the row stays.

- [ ] **Step 2: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/contacts_test.exs`
Expected: FAIL — `followed_key?/1`, `note_member/2`, `set_hidden/2` undefined; `Person` has no `friend?`.

- [ ] **Step 3: Implement the contact API**

In `lib/media_centaur/social.ex`:

```elixir
  @doc """
  Adds a friend by npub or 64-hex key, optionally under the reader's own
  name for them (UIDR-047); nil or blank is a friend without one. A key
  followed only through a relay is promoted, keeping the overrides the
  reader already set and taking the name when one is given. Idempotent on
  a friend: re-adding one changes nothing; the name is changed with
  `set_name_override/2`.
  """
  @spec add_friend(String.t(), String.t() | nil) ::
          {:ok, Contact.t()} | {:error, :invalid_pubkey | :own_key | Ecto.Changeset.t()}
  def add_friend(key, name \\ nil) when is_binary(key) and (is_binary(name) or is_nil(name)) do
    with {:ok, pubkey} <- Keys.parse_pubkey(String.trim(key)),
         :ok <- not_own_key(pubkey) do
      case Repo.get_by(Contact, pubkey: pubkey) do
        %Contact{added_at: nil} = member -> promote(member, name)
        %Contact{} = existing -> {:ok, existing}
        nil -> insert_contact(pubkey, name)
      end
    end
  end

  @doc """
  Removes a friend by public key: the added mark goes. The contact row
  stays — the reader's overrides and `hidden` wait for a return — and the
  profile and avatar go unless the key is still followed through a
  members-rule relay (`prune_if_unfollowed/1`, the one rule for every way
  a key stops being followed). Broadcasts `FriendRemoved`. A key that is
  not a friend is a no-op, and broadcasts nothing.
  """
  @spec remove_friend(String.t()) :: :ok
  def remove_friend(pubkey) when is_binary(pubkey) do
    case Repo.get_by(Contact, pubkey: String.downcase(pubkey)) do
      %Contact{added_at: added_at} = contact when added_at != nil ->
        Repo.update!(Contact.changeset(contact, %{added_at: nil}))
        prune_if_unfollowed(contact.pubkey)
        Events.broadcast(%Events.FriendRemoved{pubkey: contact.pubkey})
        :ok

      _member_only_or_absent ->
        :ok
    end
  end

  @doc "Hides or shows a person's activity for this reader. Broadcasts `ContactChanged` when it flipped."
  @spec set_hidden(String.t(), boolean()) :: {:ok, Contact.t()} | {:error, :not_a_contact}
  def set_hidden(pubkey, hidden?) when is_binary(pubkey) and is_boolean(hidden?) do
    with {:ok, contact} <- known_contact(pubkey), do: apply_change(contact, %{hidden: hidden?})
  end

  @doc "The friends — the keys the reader added by hand — oldest first."
  @spec list_friends() :: [Contact.t()]
  def list_friends,
    do:
      Repo.all(
        from(contact in Contact,
          where: not is_nil(contact.added_at),
          order_by: [contact.added_at, contact.pubkey]
        )
      )

  @doc "One contact by public key, or nil."
  @spec contact_by_pubkey(String.t()) :: Contact.t() | nil
  def contact_by_pubkey(pubkey) when is_binary(pubkey),
    do: Repo.get_by(Contact, pubkey: String.downcase(pubkey))

  @doc "Every friend's pubkey — the authors an added-rule relay's feed subscribes to."
  @spec friend_pubkeys() :: [String.t()]
  def friend_pubkeys,
    do:
      Repo.all(
        from(contact in Contact,
          where: not is_nil(contact.added_at),
          select: contact.pubkey,
          order_by: contact.pubkey
        )
      )

  @doc """
  Whether a key's events are kept: the identity, a friend, or a member of
  a relay whose follow rule is members. The one gate both ingest paths
  use. Hex in any case.
  """
  @spec followed_key?(String.t()) :: boolean()
  def followed_key?(pubkey) when is_binary(pubkey) do
    pubkey = String.downcase(pubkey)
    pubkey == Identity.pubkey() or Repo.exists?(followed_query(pubkey))
  end
```

Private helpers (replace `known_friend/1`, `insert_friend/2`, `known_key_or_error/1`; `apply_change/2` now matches `%Contact{}`):

```elixir
  defp followed_query(pubkey) do
    from(contact in Contact,
      where: contact.pubkey == ^pubkey,
      where: not is_nil(contact.added_at) or contact.pubkey in subquery(member_pubkeys_query())
    )
  end

  # The keys followed through any members-rule relay.
  defp member_pubkeys_query do
    from(member in RelayMember,
      join: relay in assoc(member, :relay),
      where: relay.follow == ^:members,
      select: member.pubkey
    )
  end

  defp followed_or_error(pubkey), do: if(followed_key?(pubkey), do: :ok, else: {:error, :unknown_author})

  defp known_contact(pubkey) do
    case contact_by_pubkey(pubkey) do
      nil -> {:error, :not_a_contact}
      contact -> {:ok, contact}
    end
  end

  defp promote(%Contact{} = member, name) do
    attrs =
      if is_binary(name) and String.trim(name) != "",
        do: %{added_at: now(), name_override: name},
        else: %{added_at: now()}

    contact = Repo.update!(Contact.changeset(member, attrs))
    Events.broadcast(%Events.FriendAdded{pubkey: contact.pubkey})
    {:ok, contact}
  end

  defp insert_contact(pubkey, name) do
    case Repo.insert(Contact.changeset(%{pubkey: pubkey, name_override: name, added_at: now()})) do
      {:ok, contact} ->
        Events.broadcast(%Events.FriendAdded{pubkey: contact.pubkey})
        {:ok, contact}

      {:error, changeset} ->
        # A concurrent insert of the same key is the re-add case, not a failure.
        if unique_violation?(changeset),
          do: {:ok, Repo.get_by!(Contact, pubkey: pubkey)},
          else: {:error, changeset}
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
```

`ingest_profile/1` uses `followed_or_error(event.pubkey)` in place of `known_key_or_error`. `set_name_override/2`, `set_show_avatar/2`, `set_hue_override/2` use `known_contact/1` and their specs say `{:error, :not_a_contact}`.

`note_member/2` is Task 4; for this task's tests to run, implement it there first or do Tasks 3 and 4 together before running. Do Task 4's Step 3 now, then run both test files.

- [ ] **Step 4: Run to verify they pass (after Task 4 Step 3)**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/`
Expected: PASS.

- [ ] **Step 5: Commit** (with Task 4)

---

### Task 4: Members — note and sweep

**Files:**
- Modify: `lib/media_centaur/social.ex`
- Test: `test/media_centaur/social/members_test.exs` (create)

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentaur.Social.MembersTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Secret
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Events.MembersChanged
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Person
  alias MediaCentaur.Social.Profile.Translation, as: ProfileTranslation

  @group "wss://group.example"
  @secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  defp profile_event(name),
    do:
      Event.sign(
        ProfileTranslation.to_event(%{name: name, avatar: nil, hue: nil}, @pubkey, 1_700_000_000),
        @secret
      )

  describe "note_member/2" do
    test "on a members-rule relay a key becomes a followed person; the first sighting broadcasts, later ones are silent" do
      {:ok, _relay} = Social.add_relay(@group, :members)
      Social.subscribe()

      assert :ok = Social.note_member(@group, String.upcase(@pubkey))
      assert_receive {:members_changed, %MembersChanged{url: "wss://group.example/"}}, 500
      assert Social.followed_key?(@pubkey)
      assert Social.list_friends() == []

      assert %{@pubkey => %Person{friend?: false, hidden: false, member_of: ["wss://group.example/"]}} =
               Social.people()

      assert :ok = Social.note_member(@group, @pubkey)
      refute_receive {:members_changed, _event}, 100
    end

    test "an added-rule relay, an unknown relay and the reader's own key are ignored" do
      {:ok, _relay} = Social.add_relay("wss://relay.example")
      assert :ignored = Social.note_member("wss://relay.example", @pubkey)
      assert :ignored = Social.note_member("wss://nowhere.example", @pubkey)
      refute Social.followed_key?(@pubkey)

      Identity.ensure()
      {:ok, _relay} = Social.add_relay(@group, :members)
      assert :ignored = Social.note_member(@group, Identity.pubkey())
      assert Social.people() |> Map.fetch!(Identity.pubkey()) |> Map.fetch!(:own?)
    end
  end

  describe "sweep_members/2" do
    test "forgets the members not seen since the connect, with their profiles, and broadcasts once" do
      {:ok, _relay} = Social.add_relay(@group, :members)
      :ok = Social.note_member(@group, @pubkey)
      {:ok, _profile} = Social.ingest_profile(profile_event("Sample Member"))
      connected_at = DateTime.utc_now()
      other = String.duplicate("b", 64)
      :ok = Social.note_member(@group, other)
      Social.subscribe()

      assert :ok = Social.sweep_members(@group, connected_at)
      assert_receive {:members_changed, %MembersChanged{url: "wss://group.example/"}}, 500
      refute Social.followed_key?(@pubkey)
      assert Social.followed_key?(other)
      refute Map.has_key?(Social.people(), @pubkey)
      assert Social.ingest_profile(profile_event("Back")) == {:error, :unknown_author}

      assert :ok = Social.sweep_members(@group, connected_at)
      refute_receive {:members_changed, _event}, 100
      assert :ignored = Social.sweep_members("wss://nowhere.example", connected_at)
    end

    test "a swept member who is also a friend stays a friend" do
      {:ok, _relay} = Social.add_relay(@group, :members)
      :ok = Social.note_member(@group, @pubkey)
      {:ok, _friend} = Social.add_friend(@pubkey, "Sample Friend")

      assert :ok = Social.sweep_members(@group, DateTime.utc_now())
      assert Social.followed_key?(@pubkey)
      assert %{@pubkey => %Person{friend?: true, member_of: []}} = Social.people()
    end
  end

  describe "a relay going" do
    test "removing a relay forgets its members; switching it to added does the same" do
      {:ok, _relay} = Social.add_relay(@group, :members)
      :ok = Social.note_member(@group, @pubkey)
      {:ok, _profile} = Social.ingest_profile(profile_event("Sample Member"))

      {:ok, _relay} = Social.set_follow(@group, :added)
      refute Social.followed_key?(@pubkey)
      assert Repo.aggregate(MediaCentaur.Social.Profile, :count) == 0

      {:ok, _relay} = Social.set_follow(@group, :members)
      :ok = Social.note_member(@group, @pubkey)
      :ok = Social.remove_relay(@group)
      refute Social.followed_key?(@pubkey)
      assert Repo.aggregate(MediaCentaur.Social.RelayMember, :count) == 0
    end
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/members_test.exs`
Expected: FAIL — `note_member/2`, `sweep_members/2` undefined.

- [ ] **Step 3: Implement**

In `lib/media_centaur/social.ex`:

```elixir
  # --- members -----------------------------------------------------------------

  @doc """
  Records that `pubkey` published on the relay at `url`, for the sync loop:
  on a relay whose follow rule is members the key becomes followed, with a
  contact row when none exists, and `seen_at` moves to now; `:ignored` on
  an added-rule relay, an unknown relay, or the reader's own key.
  Broadcasts `MembersChanged` the first time a key is seen on a relay.
  """
  @spec note_member(String.t(), String.t()) :: :ok | :ignored
  def note_member(url, pubkey) when is_binary(url) and is_binary(pubkey) do
    pubkey = String.downcase(pubkey)

    case get_relay(url) do
      %Relay{follow: :members} = relay ->
        if pubkey == Identity.pubkey(), do: :ignored, else: record_member(relay, pubkey)

      _added_or_unknown ->
        :ignored
    end
  end

  @doc """
  Forgets the members of the relay at `url` that the connect begun at
  `before` did not see again, for the sync loop at the end of a read: a key
  the relay no longer serves stops being followed through it, and loses
  its profile and avatar unless still followed another way. Broadcasts
  `MembersChanged` when any row went. `:ignored` for an unknown relay.
  """
  @spec sweep_members(String.t(), DateTime.t()) :: :ok | :ignored
  def sweep_members(url, %DateTime{} = before) when is_binary(url) do
    case get_relay(url) do
      nil ->
        :ignored

      relay ->
        stale = from(member in RelayMember, where: member.relay_id == ^relay.id and member.seen_at < ^before)
        pubkeys = Repo.all(from(member in stale, select: member.pubkey))

        if pubkeys != [] do
          Repo.delete_all(stale)
          Enum.each(pubkeys, &prune_if_unfollowed/1)
          Events.broadcast(%Events.MembersChanged{url: relay.url})
        end

        :ok
    end
  end

  defp record_member(%Relay{} = relay, pubkey) do
    seen_at = DateTime.utc_now()

    case Repo.get_by(RelayMember, relay_id: relay.id, pubkey: pubkey) do
      nil ->
        Repo.insert!(Contact.changeset(%{pubkey: pubkey}), on_conflict: :nothing, conflict_target: :pubkey)
        Repo.insert!(RelayMember.changeset(%{relay_id: relay.id, pubkey: pubkey, seen_at: seen_at}))
        Events.broadcast(%Events.MembersChanged{url: relay.url})

      member ->
        Repo.update!(Ecto.Changeset.change(member, seen_at: seen_at))
    end

    :ok
  end

  # A key followed neither by the reader's hand nor through any relay
  # keeps its contact row — its overrides and `hidden` wait for a return —
  # but not its profile and avatar, which `people/0` would never show and
  # `ingest_profile/1` would refuse to refresh.
  defp prune_if_unfollowed(pubkey), do: unless(followed_key?(pubkey), do: delete_profile(pubkey))
```

Replace Task 2's `forget_members/1`:

```elixir
  defp forget_members(%Relay{id: relay_id}) do
    rows = from(member in RelayMember, where: member.relay_id == ^relay_id)
    pubkeys = Repo.all(from(member in rows, select: member.pubkey))
    Repo.delete_all(rows)
    Enum.each(pubkeys, &prune_if_unfollowed/1)
    :ok
  end
```

And `remove_relay/1` prunes too (the FK cascade deletes the rows; the profiles need the hand):

```elixir
      relay ->
        pubkeys = Repo.all(from(member in RelayMember, where: member.relay_id == ^relay.id, select: member.pubkey))
        Repo.delete!(relay)
        Enum.each(pubkeys, &prune_if_unfollowed/1)
        Events.broadcast(%Events.RelayRemoved{url: relay.url})
        :ok
```

- [ ] **Step 4: Run to verify Tasks 3 and 4 pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/`
Expected: PASS except the `Person` `friend?`/`member_of` assertions, which Task 5 satisfies. If `on_conflict: :nothing` with `conflict_target` is refused by the adapter, drop `conflict_target` (SQLite's `ON CONFLICT DO NOTHING` needs none).

- [ ] **Step 5: Commit after Task 5**

---

### Task 5: `Person` and `people/0`

**Files:**
- Modify: `lib/media_centaur/social/person.ex`
- Modify: `lib/media_centaur/social.ex`
- Test: `test/media_centaur/social/person_test.exs` (create, `async: true`)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Social.PersonTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Social.Person

  test "member_hosts/1 names the relays a person is followed through, by host" do
    person = %Person{member_of: ["wss://group.example/", "ws://127.0.0.1:2173/"]}
    assert Person.member_hosts(person) == ["group.example", "127.0.0.1"]
    assert Person.member_hosts(%Person{}) == []
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/person_test.exs`
Expected: FAIL — no `member_of` key.

- [ ] **Step 3: Implement**

In `lib/media_centaur/social/person.ex` extend the moduledoc with: `friend?` says whether the reader added the key by hand; `hidden` is the reader's switch keeping the person's activity off every surface but the Friends tab's hidden group; `member_of` is the relays (URLs) the person is followed through, `[]` for a friend added by key alone, `member_hosts/1` their hosts for the card's foot. Struct and type:

```elixir
  defstruct [
    :pubkey,
    :name_override,
    :published_name,
    :avatar_url,
    :published_hue,
    :hue_override,
    :short_npub,
    :added_on,
    own?: false,
    friend?: false,
    hidden: false,
    show_avatar: true,
    member_of: []
  ]
```

Add `friend?: boolean(), hidden: boolean(), member_of: [String.t()]` to `@type t` and:

```elixir
  @doc "The hosts of the relays the person is followed through, for the card's foot; `[]` for a friend added by key alone."
  @spec member_hosts(t()) :: [String.t()]
  def member_hosts(%__MODULE__{member_of: urls}), do: Enum.map(urls, &(URI.parse(&1).host || &1))
```

In `lib/media_centaur/social.ex` replace `people/0` and `person_for/2`:

```elixir
  @doc """
  Every person this reader follows, by public key (ADR-074): the identity's
  own when one exists, every friend, and every member of a members-rule
  relay — hidden ones included, flagged — each as a `Person` with the name
  and the hue their `Profile` published, when one is stored, and its
  avatar when the reader shows it. The one place a contact row and a
  profile become what the reader sees.
  """
  @spec people() :: %{optional(String.t()) => Person.t()}
  def people do
    # Five fields per row: `raw_event` carries the encoded avatar and is
    # for republish, not for a page load.
    profiles =
      Profile
      |> select([p], struct(p, [:pubkey, :name, :avatar_type, :hue, :created_at]))
      |> Repo.all()
      |> Map.new(&{&1.pubkey, &1})

    memberships =
      from(member in RelayMember,
        join: relay in assoc(member, :relay),
        where: relay.follow == ^:members,
        select: {member.pubkey, relay.url}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    followed =
      Contact
      |> Repo.all()
      |> Enum.filter(&(Contact.friend?(&1) or is_map_key(memberships, &1.pubkey)))
      |> Map.new(
        &{&1.pubkey, person_for(&1, Map.get(profiles, &1.pubkey), Map.get(memberships, &1.pubkey, []))}
      )

    case Identity.pubkey() do
      nil -> followed
      me -> Map.put(followed, me, own_person_for(me, Map.get(profiles, me)))
    end
  end

  @doc "The followed people the surfaces draw: `people/0` less the hidden. The one place hidden is applied."
  @spec visible_people() :: %{optional(String.t()) => Person.t()}
  def visible_people, do: Map.reject(people(), fn {_pubkey, person} -> person.hidden end)
```

```elixir
  defp person_for(%Contact{} = contact, profile, relay_urls) do
    %Person{
      pubkey: contact.pubkey,
      name_override: contact.name_override,
      published_name: profile && profile.name,
      avatar_url: if(contact.show_avatar, do: avatar_url(profile)),
      show_avatar: contact.show_avatar,
      published_hue: profile && profile.hue,
      hue_override: contact.hue_override,
      own?: false,
      friend?: Contact.friend?(contact),
      hidden: contact.hidden,
      member_of: Enum.sort(relay_urls),
      short_npub: short_npub(contact.pubkey),
      added_on: contact.added_at && DateTime.to_date(contact.added_at)
    }
  end
```

Update the `Social` moduledoc's first paragraph:

```elixir
  Bounded context for the friend network's configuration: this install's
  identity (`Social.Identity`), the relay list (`Social.Relay`, each under
  the reader's follow rule), the live connections keyed by it
  (`Social.Connections`), the contacts — one row per key the reader has a
  view of, a friend when they added it by hand (`Social.Contact`), the
  members observed on a members-rule relay (`Social.RelayMember`) — and
  each key's published profile (`Social.Profile`), saved by the reader for
  their own key and ingested for a followed one. `people/0` reads the
  identity and every followed key as `Social.Person`, the one read model
  every surface draws a person from (ADR-074).
```

- [ ] **Step 4: Run the Social tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/`
Expected: PASS.

- [ ] **Step 5: Commit Tasks 3–5**

```bash
git add lib/media_centaur/social.ex lib/media_centaur/social/person.ex test/media_centaur/social
git commit -m "feat(social): contacts follow by hand or through a members-rule relay; hidden people"
```

---

### Task 6: Activities — the gate and the hidden

**Files:**
- Modify: `lib/media_centaur/activities.ex`
- Test: `test/media_centaur/activities/activities_test.exs`

- [ ] **Step 1: Write the failing tests**

In the describe that holds the `unknown_author` ingest test, add:

```elixir
    test "a member of a members-rule relay is a known author" do
      {:ok, _relay} = Social.add_relay("wss://group.example", :members)
      :ok = Social.note_member("wss://group.example", @friend_pubkey)
      event = friend_event(title(603), "x", 1_700_000_000)

      assert {:ok, _activity} = Activities.ingest(event)
      assert [%{author: %Person{friend?: false}}] = Activities.list_activities()
    end

    test "a hidden person's activity is kept but shown by neither reader" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      {:ok, _activity} = Activities.ingest(friend_event(title(603), "x", 1_700_000_000))

      {:ok, _contact} = Social.set_hidden(@friend_pubkey, true)
      assert Activities.list_activities() == []
      assert Activities.activity_for([{603, :movie}]) == %{}

      {:ok, _contact} = Social.set_hidden(@friend_pubkey, false)
      assert [%{activity: %{tmdb_id: 603}}] = Activities.list_activities()
      assert %{{603, :movie} => [_row]} = Activities.activity_for([{603, :movie}])
    end
```

(`friend_event/3`, `title/1` and `@friend_pubkey` already exist in that file; alias `MediaCentaur.Social.Person`.)

- [ ] **Step 2: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/activities/activities_test.exs`
Expected: FAIL — `Social.known_key?/1` undefined (compile error) — then the hidden assertions.

- [ ] **Step 3: Implement**

```elixir
  defp known_author(pubkey), do: if(Social.followed_key?(pubkey), do: :ok, else: {:error, :unknown_author})

  # `get_row/1` keeps `Social.people/0`: a row reached by id is the
  # reader's own choice.
```

`list_activities/0` and `activity_for/1` call `Social.visible_people()` where they called `Social.people()`. Update both `@doc`s: "A row whose author is not followed, or is hidden, is left out".

- [ ] **Step 4: Run to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur/activities/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/activities.ex test/media_centaur/activities/activities_test.exs
git commit -m "feat(activities): followed keys are the gate; hidden people make no row"
```

---

### Task 7: Sync loop

**Files:**
- Modify: `lib/media_centaur/relay_sync.ex`
- Modify: `test/support/nostr/fake_relay.ex`
- Test: `test/media_centaur/relay_sync_test.exs`

- [ ] **Step 1: Add `FakeRelay.replace_events/2`**

In `test/support/nostr/fake_relay.ex` after `push/2`:

```elixir
  @doc "Replaces the stored events new connections are served; open sockets keep what they had, so `drop/1` next."
  @spec replace_events(t(), [Event.t()]) :: :ok
  def replace_events(relay, events), do: Agent.update(relay.name, &Map.put(&1, :events, events))
```

- [ ] **Step 2: Write the failing tests**

In `test/media_centaur/relay_sync_test.exs` add (aliases: `MediaCentaur.Social.Events.MembersChanged`, `MediaCentaur.Social.Relay`):

```elixir
  @member_secret Secret.wrap(String.duplicate("0", 63) <> "5")
  @member_pubkey Keys.pubkey(Secret.wrap(String.duplicate("0", 63) <> "5"))

  defp member_event(id, created_at),
    do:
      Event.sign(
        %{Translation.to_event(:review, title(id), [note: "from a member"], @member_pubkey) | created_at: created_at},
        @member_secret
      )

  test "a members-rule relay is read without an author list and an unknown member's event is kept" do
    Social.subscribe()
    relay = FakeRelay.start(events: [member_event(1, System.os_time(:second) - 10)])
    {:ok, _row} = Social.add_relay(relay.url, :members)

    assert_receive {:relay_in, ["REQ", "feed", filter]}, 5_000
    refute Map.has_key?(filter, "authors")
    assert_receive {:members_changed, %MembersChanged{}}, 5_000
    assert_receive {:activity_received, _event}, 5_000

    assert [%{activity: %{tmdb_id: 1}, author: %Person{friend?: false, member_of: [_url]}}] =
             Activities.list_activities()

    await_supervised_tasks()
  end

  test "a member the relay stops serving is forgotten on the next read" do
    Social.subscribe()
    relay = FakeRelay.start(events: [member_event(1, System.os_time(:second) - 10)])
    {:ok, _row} = Social.add_relay(relay.url, :members)
    assert_receive {:members_changed, %MembersChanged{}}, 5_000
    assert Social.followed_key?(@member_pubkey)

    FakeRelay.replace_events(relay, [])
    FakeRelay.drop(relay)

    assert_receive {:members_changed, %MembersChanged{}}, 5_000
    refute Social.followed_key?(@member_pubkey)
    assert Activities.list_activities() == []
    await_supervised_tasks()
  end

  test "changing a relay's follow rule re-issues the feed" do
    relay = FakeRelay.start()
    {:ok, _row} = Social.add_relay(relay.url)
    assert_receive {:relay_in, ["REQ", "feed", %{"authors" => _authors}]}, 5_000

    {:ok, %Relay{follow: :members}} = Social.set_follow(relay.url, :members)
    assert_receive {:relay_in, ["REQ", "feed", filter]}, 5_000
    refute Map.has_key?(filter, "authors")
    await_supervised_tasks()
  end
```

- [ ] **Step 3: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/relay_sync_test.exs`
Expected: the three new tests FAIL (authors present; no `members_changed`).

- [ ] **Step 4: Implement**

In `lib/media_centaur/relay_sync.ex`:

```elixir
  defstruct seen: %{}, pages: %{}, connected: %{}, page_limit: @default_page_limit
```

```elixir
  @impl true
  def handle_info({:relay_connection, url, :connected}, state) do
    Connections.subscribe(url, own_sub(url), [own_filter()])

    state =
      state
      |> put_in([Access.key(:seen), url], MapSet.new())
      |> put_in([Access.key(:connected), url], DateTime.utc_now())
      |> subscribe_feed(url, nil, false)

    {:noreply, state}
  end

  def handle_info({:relay_connection, url, {:event, sub_id, event}}, state) do
    state = if sub_id == own_sub(url), do: mark_seen(state, url, event.id), else: state
    state = if sub_id == @feed, do: note_page_event(state, url, event), else: state
    # Before the owner's ingest: on a members-rule relay the author becomes
    # followed by being served, and the gate must already know.
    if sub_id == @feed, do: Social.note_member(url, event.pubkey)

    case ingest(event) do
      ...unchanged...
    end

    {:noreply, state}
  end
```

```elixir
  def handle_info({:friend_added, _event}, state), do: {:noreply, resubscribe(state)}
  def handle_info({:friend_removed, _event}, state), do: {:noreply, resubscribe(state)}
  def handle_info({:relay_changed, _event}, state), do: {:noreply, resubscribe(state)}
```

```elixir
  defp subscribe_feed(state, url, until, paging?) do
    Connections.subscribe(url, @feed, [feed_filter(url, until, state.page_limit)])
    put_in(state, [Access.key(:pages), url], %Page{paging?: paging?})
  end

  defp next_page(state, url) do
    case Map.get(state.pages, url) do
      %Page{count: count, oldest: oldest} when count >= state.page_limit and is_integer(oldest) ->
        subscribe_feed(state, url, oldest - 1, true)

      %Page{paging?: true} ->
        state |> sweep(url) |> subscribe_feed(url, nil, false)

      _short_first_page_or_unknown ->
        sweep(state, url)
    end
  end

  # The read is complete: every member the relay still serves has been
  # noted since the connect; the rest are forgotten (a no-op on an
  # added-rule relay, which has none).
  defp sweep(state, url) do
    case Map.get(state.connected, url) do
      nil -> :ok
      connected_at -> Social.sweep_members(url, connected_at)
    end

    state
  end
```

```elixir
  # On a members-rule relay the relay restricts the read to its members
  # itself, so no author list goes out; on an added-rule relay the
  # authors are the friends and the reader. Before an identity exists
  # there is nothing to subscribe as — and no connection either, since
  # `Connections` starts none — but the nil would still reach the wire
  # as an author, so it is filtered out.
  defp feed_filter(url, until, limit) do
    case Social.get_relay(url) do
      %{follow: :members} ->
        Filter.new(kinds: kinds(), until: until, limit: limit)

      _added_or_unknown ->
        authors = Enum.reject(Enum.uniq([Identity.pubkey() | Social.friend_pubkeys()]), &is_nil/1)
        Filter.new(authors: authors, kinds: kinds(), until: until, limit: limit)
    end
  end
```

Moduledoc: in the first bullet, "subscribe `"feed"` (authors = friends ++ self on an added-rule relay, no author list on a members-rule one, every activity kind, 5 and the profile's 12160, `limit` = the page size)"; add a bullet "`{:event, "feed", event}` → `Social.note_member/2` first, so a member of a members-rule relay is followed before its event is judged; then route as above."; add "after a read completes (a short page) → `Social.sweep_members/2` with the connect time, forgetting members the relay no longer serves"; and "Consumes `social:updates`: a roster change or a relay's follow rule change re-issues `"feed"` on every connected relay."

- [ ] **Step 5: Run to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur/relay_sync_test.exs test/media_centaur/social/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/relay_sync.ex test/support/nostr/fake_relay.ex test/media_centaur/relay_sync_test.exs
git commit -m "feat(relay-sync): read a members-rule relay whole; note members before ingest, sweep after the read"
```

---

### Task 8: Settings — the rule on the add form and each row

**Files:**
- Modify: `lib/media_centaur_web/components/settings.ex`
- Create: `storybook/settings/settings_select.story.exs`
- Modify: `lib/media_centaur_web/live/settings_live/social_section.ex`
- Modify: `lib/media_centaur_web/live/settings_live.ex`
- Test: `test/media_centaur_web/live/settings_live_social_test.exs`, `test/media_centaur_web/live/settings_live/social_section_test.exs` (create, `async: true`)

- [ ] **Step 1: Write the failing tests**

`test/media_centaur_web/live/settings_live/social_section_test.exs`:

```elixir
defmodule MediaCentaurWeb.SettingsLive.SocialSectionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.SettingsLive.SocialSection

  test "parse_follow/1 reads the control's value; anything else is added" do
    assert SocialSection.parse_follow("members") == :members
    assert SocialSection.parse_follow("added") == :added
    assert SocialSection.parse_follow(nil) == :added
    assert SocialSection.parse_follow("x") == :added
  end

  test "follow_options/0 lists added first, each under its label" do
    assert SocialSection.follow_options() == [
             {"added", "Only people I add"},
             {"members", "Everyone on this relay"}
           ]
  end
end
```

In `test/media_centaur_web/live/settings_live_social_test.exs`, next to the existing add-relay test (line ~471):

```elixir
    test "a relay is added under a follow rule and its row changes it", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live_async!(conn, @section)

      view
      |> form("#add-relay-form", %{"url" => "wss://group.example", "follow" => "members"})
      |> render_submit()

      assert %Relay{follow: :members} = Social.get_relay("wss://group.example")
      assert has_element?(view, "#relay-wss-group-example-follow option[value='members'][selected]")

      view |> form("#relay-wss-group-example-follow", %{"follow" => "added"}) |> render_change()
      assert %Relay{follow: :added} = Social.get_relay("wss://group.example")
      assert has_element?(view, "#relay-wss-group-example-follow option[value='added'][selected]")
    end
```

(alias `MediaCentaur.Social.Relay`; follow the file's own setup for the identity and `@section`.)

- [ ] **Step 2: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live/social_section_test.exs test/media_centaur_web/live/settings_live_social_test.exs`
Expected: FAIL — functions undefined; no `follow` control.

- [ ] **Step 3: Extract `settings_select/1`**

In `lib/media_centaur_web/components/settings.ex`, before `settings_select_row`:

```elixir
  attr :name, :string, required: true
  attr :options, :list, required: true, doc: "`[{value, label}]`."

  attr :selected, :any,
    required: true,
    doc: "the current option value — a string or atom, whatever the owner stores. Compared with `==`."

  attr :id, :string, default: nil
  attr :aria_label, :string, default: nil, doc: "when no visible label names the control."

  @doc """
  The house native select (UIDR-041 §2), on its own: inside a form that
  saves on change (`settings_select_row`) or on submit (a field of an add
  form). Nav item; the chosen option carries `selected`.
  """
  def settings_select(assigns) do
    ~H"""
    <select
      id={@id}
      name={@name}
      aria-label={@aria_label}
      class="select select-bordered select-sm shrink-0 max-w-full text-sm"
      data-nav-item
      tabindex="0"
    >
      <option :for={{value, label} <- @options} value={value} selected={value == @selected}>
        {label}
      </option>
    </select>
    """
  end
```

and `settings_select_row` renders `<.settings_select name={@name} options={@options} selected={@selected} />` in place of its inline `<select>`.

`storybook/settings/settings_select.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Settings.SettingsSelect do
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.Components.Settings.settings_select/1
  def render_source, do: :function

  @follow [
    {"added", "Only people I add"},
    {"members", "Everyone on this relay"}
  ]

  def variations do
    [
      %Variation{
        id: :follow_rule,
        description: "The bare select, as a field of a submit form: a relay's follow rule.",
        attributes: %{name: "follow", options: @follow, selected: "added", aria_label: "Who to follow"}
      },
      %Variation{
        id: :second_selected,
        description: "The second option chosen.",
        attributes: %{name: "follow", options: @follow, selected: "members", aria_label: "Who to follow"}
      }
    ]
  end
end
```

- [ ] **Step 4: The section**

In `lib/media_centaur_web/live/settings_live/social_section.ex` add the public helpers (and `alias MediaCentaur.Social.Relay` if not present):

```elixir
  @follow_options [{"added", "Only people I add"}, {"members", "Everyone on this relay"}]

  @doc "The follow rule control's options, added first: the two rules under the words the reader chooses between."
  @spec follow_options() :: [{String.t(), String.t()}]
  def follow_options, do: @follow_options

  @doc "The rule a control's value names, read off `Relay`'s enum; anything else — a missing field included — is added."
  @spec parse_follow(String.t() | nil) :: Relay.follow()
  def parse_follow(value),
    do: Enum.find(Ecto.Enum.values(Relay, :follow), :added, &(Atom.to_string(&1) == value))
```

Relays card description: `"The servers your activity is published to and read from. On your group's own relay choose Everyone on this relay to follow every member; on a larger relay choose Only people I add."`

Row actions:

```heex
            <:actions>
              <form
                id={relay_dom_id(relay.url) <> "-follow"}
                phx-change="set_relay_follow"
                class="contents"
              >
                <input type="hidden" name="url" value={relay.url} />
                <.settings_select
                  name="follow"
                  options={follow_options()}
                  selected={Atom.to_string(relay.follow)}
                  aria_label="Who to follow on this relay"
                />
              </form>
              <.button ...Remove unchanged... />
            </:actions>
```

Add form: `class="flex flex-wrap items-center gap-2 pt-1"`, and between the input and the button:

```heex
          <.settings_select
            name="follow"
            options={follow_options()}
            selected="added"
            aria_label="Who to follow on this relay"
          />
```

`settings_select` must be imported where `settings_input` is.

In `lib/media_centaur_web/live/settings_live.ex`:

```elixir
  def handle_event("add_relay", %{"url" => url} = params, socket) do
    case Social.add_relay(url, SocialSection.parse_follow(params["follow"])) do
      ...unchanged...
    end
  end

  # The relay row's select; an unknown URL (removed in another tab) just reloads the rows.
  def handle_event("set_relay_follow", %{"url" => url, "follow" => follow}, socket) do
    _result = Social.set_follow(url, SocialSection.parse_follow(follow))
    {:noreply, load_relays(socket)}
  end
```

and `when tag in [:relay_added, :relay_removed, :relay_changed]`. The moduledoc's event list in `social_section.ex` gains `set_relay_follow`.

- [ ] **Step 5: Run to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live/social_section_test.exs test/media_centaur_web/live/settings_live_social_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/components/settings.ex storybook/settings/settings_select.story.exs lib/media_centaur_web/live/settings_live/social_section.ex lib/media_centaur_web/live/settings_live.ex test/media_centaur_web
git commit -m "feat(settings): choose who to follow on each relay"
```

---

### Task 9: Person card foot and the hidden row

**Files:**
- Modify: `lib/media_centaur_web/components/social/person_card.ex`
- Create: `lib/media_centaur_web/components/social/hidden_person_row.ex`
- Modify: `storybook/social/person_card.story.exs`
- Create: `storybook/social/hidden_person_row.story.exs`

- [ ] **Step 1: The foot**

In `person_card.ex` replace the foot's last `<div class="flex items-center justify-between">`:

```heex
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm text-base-content/65">
            <code>{@person.short_npub}</code> · {provenance(@person)}
          </span>
          <span class="flex items-center gap-2">
            <.button
              variant="neutral"
              size="sm"
              phx-click="set_hidden"
              phx-value-pubkey={@person.pubkey}
              phx-value-hide="true"
              data-nav-item
              tabindex="0"
            >
              Hide
            </.button>
            <.button
              :if={@person.friend?}
              variant="dismiss"
              size="sm"
              phx-click="remove_friend"
              phx-value-pubkey={@person.pubkey}
              data-nav-item
              tabindex="0"
            >
              Remove friend
            </.button>
          </span>
        </div>
```

```elixir
  # How the reader came to follow the person: the day they added them, else
  # the relay whose members they follow.
  defp provenance(%Person{friend?: true, added_on: %Date{} = added_on}),
    do: "added " <> Calendar.strftime(added_on, "%b %-d")

  defp provenance(%Person{} = person), do: "on " <> Enum.join(Person.member_hosts(person), ", ")
```

Moduledoc: the foot's last line is "the key, how the reader follows them — *added* and the date for a friend, *on* the relay's host for a member — **Hide**, which pushes `set_hidden` with the key and `hide` `"true"`, and, for a friend only, Remove friend".

- [ ] **Step 2: The hidden row**

`lib/media_centaur_web/components/social/hidden_person_row.ex`:

```elixir
defmodule MediaCentaurWeb.Components.Social.HiddenPersonRow do
  @moduledoc """
  One hidden person in the Friends tab's hidden group: the identity tile,
  the name the reader sees, and **Show**, which pushes `set_hidden` with
  the key and `hide` `"false"`. Pure rendering of a `Social.Person`; the
  acts are not drawn, since hidden means unseen.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1]

  alias MediaCentaur.Format
  alias MediaCentaur.Social.Person
  alias MediaCentaurWeb.Components.Social.IdentityTile

  attr :id, :string, required: true
  attr :person, Person, required: true, doc: "the person as the reader sees them; `hidden` is true"

  def hidden_person_row(assigns) do
    ~H"""
    <li id={@id} class="flex items-center gap-3 px-1 py-1" data-component="hidden-person-row">
      <IdentityTile.identity_tile {IdentityTile.person_attrs(@person)} size={40} />
      <span class="min-w-0 flex-1 truncate" data-role="name">{Format.person_name(@person)}</span>
      <.button
        variant="neutral"
        size="xs"
        phx-click="set_hidden"
        phx-value-pubkey={@person.pubkey}
        phx-value-hide="false"
        data-nav-item
        tabindex="0"
      >
        Show
      </.button>
    </li>
    """
  end
end
```

`storybook/social/hidden_person_row.story.exs`:

```elixir
defmodule MediaCentaurWeb.Storybook.Social.HiddenPersonRow do
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Social.Person

  def function, do: &MediaCentaurWeb.Components.Social.HiddenPersonRow.hidden_person_row/1
  def render_source, do: :function

  @list ~s(<ul class="w-[480px]"><.psb-variation/></ul>)

  defp hidden(overrides \\ %{}) do
    Map.merge(
      %Person{
        pubkey: "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
        name_override: "Sample Friend",
        short_npub: "npub1lyy9…8z4h",
        hidden: true,
        friend?: true
      },
      overrides
    )
  end

  def variations do
    [
      %Variation{
        id: :named,
        description: "A hidden friend: tile, name, Show",
        template: @list,
        attributes: %{id: "hidden-1", person: hidden()}
      },
      %Variation{
        id: :unnamed_member,
        description: "A hidden member with no name: the person glyph and Unnamed",
        template: @list,
        attributes: %{id: "hidden-2", person: hidden(%{name_override: nil, friend?: false})}
      }
    ]
  end
end
```

- [ ] **Step 3: Card story fixtures**

In `storybook/social/person_card.story.exs`: `friend/0` gains `friend?: true`; add

```elixir
  defp member,
    do: %{friend() | friend?: false, added_on: nil, member_of: ["wss://group.example/"], name_override: nil, published_name: "Sample Member"}
```

and the variation after `:page_opened`:

```elixir
      %Variation{
        id: :page_opened_member,
        description:
          "The opened card of a member followed through a relay set to Everyone on this relay: the foot says which relay, offers Hide, and no Remove friend",
        attributes: %{person: member(), acts: seven_acts(), width: :page, opened?: true},
        template: @page
      },
```

- [ ] **Step 4: Render the stories**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/storybook_compile_test.exs test/media_centaur_web/storybook_render_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/components/social storybook/social
git commit -m "feat(ui): the person card's foot says how the reader follows them and offers Hide"
```

---

### Task 10: Friends tab and feed — hidden group, member cards, copy

**Files:**
- Modify: `lib/media_centaur_web/live/social_live/people.ex`
- Modify: `lib/media_centaur_web/live/social_live.ex`
- Modify: `lib/media_centaur_web/live/social_live/feed_entries.ex` (doc only)
- Modify: `lib/media_centaur_web/live/status_live.ex`, `lib/media_centaur_web/components/status_widgets/social.ex`
- Test: `test/media_centaur_web/live/social_live/people_test.exs` (exists? if not, create `async: true`), `test/media_centaur_web/live/social_live_test.exs`

- [ ] **Step 1: Write the failing tests**

`People` (pure):

```elixir
  test "hidden/1 lists the hidden people by name" do
    shown = %Person{pubkey: String.duplicate("a", 64), name_override: "Shown"}
    hidden_a = %Person{pubkey: String.duplicate("b", 64), name_override: "Zed", hidden: true}
    hidden_b = %Person{pubkey: String.duplicate("c", 64), name_override: "Amy", hidden: true}
    people = Map.new([shown, hidden_a, hidden_b], &{&1.pubkey, &1})

    assert [^hidden_b, ^hidden_a] = People.hidden(people)
  end
```

`social_live_test.exs`, in `describe "friends tab"`:

```elixir
    test "Hide takes a friend off the tab and the feed; the hidden group shows them again", %{conn: conn} do
      Identity.ensure()
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Sample Friend")
      movie = Title.new!(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie 777"})
      {:ok, _review} = Activities.ingest(signed(:review, movie, note: "words"))
      {:ok, view, _html} = live(conn, "/social/friends")

      view |> element(friend_card()) |> render_click()
      view |> element(friend_card() <> " footer button", "Hide") |> render_click()
      render_until(view, fn _html -> not has_element?(view, friend_card()) end)
      assert has_element?(view, "#friends-hidden [data-component='hidden-person-row']", "Sample Friend")

      {:ok, feed, _html} = live(conn, "/social")
      refute has_element?(feed, "[data-component='feed-row']")

      view |> element("#friends-hidden button", "Show") |> render_click()
      render_until(view, fn _html -> has_element?(view, friend_card()) end)
      refute has_element?(view, "#friends-hidden")
    end

    test "a member's card names the relay and offers Hide, not Remove friend", %{conn: conn} do
      Identity.ensure()
      {:ok, _relay} = Social.add_relay("wss://group.example", :members)
      :ok = Social.note_member("wss://group.example", @friend_pubkey)
      {:ok, view, _html} = live(conn, "/social/friends")

      view |> element(friend_card()) |> render_click()
      assert has_element?(view, friend_card() <> " footer", "on group.example")
      assert has_element?(view, friend_card() <> " footer button", "Hide")
      refute has_element?(view, friend_card() <> " footer button", "Remove friend")
    end
```

- [ ] **Step 2: Run to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/social_live_test.exs test/media_centaur_web/live/social_live/`
Expected: FAIL.

- [ ] **Step 3: `People`**

In `people.ex` add (`build/3` is handed `Social.visible_people/0`, so it never meets a hidden person):

```elixir
  @doc "The hidden people, by name: the Friends tab's hidden group, which `build/3` leaves out."
  @spec hidden(%{optional(String.t()) => Person.t()}) :: [Person.t()]
  def hidden(people),
    do: people |> Map.values() |> Enum.filter(& &1.hidden) |> Enum.sort_by(&Format.person_name/1)
```

Moduledoc: "then every followed person" in place of "then friends", and that the host hands it `Social.visible_people/0`; name the hidden group.

- [ ] **Step 4: `SocialLive`**

- mount assigns: add `hidden_people: []`.
- `@people_tags [:friend_added, :friend_removed, :contact_changed, :members_changed, :identity_changed, :profile_updated]`.
- `load_people/1` reads the visible map for the cards, the feed's authors and the count, and the whole map for the hidden group:

```elixir
  defp load_people(socket) do
    people = Social.visible_people()

    assign(socket,
      people_by_pubkey: people,
      hidden_people: People.hidden(Social.people()),
      friend_count: Enum.count(people, fn {_pubkey, person} -> not person.own? end)
    )
  end
```

- Status tile: `lib/media_centaur_web/live/status_live.ex` line 211 becomes `friend_count: Enum.count(Social.visible_people(), fn {_pubkey, person} -> not person.own? end)`; in `lib/media_centaur_web/components/status_widgets/social.ex` the attr doc reads `"how many people the reader follows and shows"` and the line reads `{@friend_count} people · …`. Same count as the Friends tab's, from the same function.
- Events: every `{:error, :not_a_friend}` becomes `{:error, :not_a_contact} -> {:noreply, flash_not_a_contact(socket)}`; rename the helper and its copy: `"That person is no longer on your list"`. Add:

```elixir
  # The opened card's foot and the hidden group: `hide` is the value to set.
  def handle_event("set_hidden", %{"pubkey" => pubkey, "hide" => hide}, socket) do
    case Social.set_hidden(pubkey, hide == "true") do
      {:ok, _contact} -> {:noreply, socket}
      {:error, :not_a_contact} -> {:noreply, flash_not_a_contact(socket)}
    end
  end
```

- Template, after the `#friends-grid` div and before `<AddFriendBlock.add_friend_block />`:

```heex
                <div :if={@hidden_people != []} id="friends-hidden" class="space-y-2" data-nav-zone="hidden-people">
                  <h3 class="px-1 text-sm font-medium uppercase tracking-wider text-base-content/55">
                    Hidden
                  </h3>
                  <ul class="space-y-1">
                    <HiddenPersonRow.hidden_person_row
                      :for={person <- @hidden_people}
                      id={PersonCard.dom_id(person) <> "-hidden"}
                      person={person}
                    />
                  </ul>
                </div>
```

(alias `MediaCentaurWeb.Components.Social.HiddenPersonRow`.)

- Copy:

```elixir
  defp feed_empty_body(:no_friends),
    do:
      "You are on a relay. Add a friend by the public key they give you, or set your group's own relay to Everyone on this relay under Settings → Social."

  defp friends_empty_body(:no_friends),
    do:
      "Paste the key they give you below, or set your group's own relay to Everyone on this relay under Settings → Social."
```

- `feed_entries.ex` `empty_reason/3` doc: "given whether a relay exists and how many people the reader follows and shows".
- Moduledoc of `SocialLive`: name `set_hidden` beside the foot's other events and the hidden group.

- [ ] **Step 5: Run to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/social_live_test.exs test/media_centaur_web/live/social_live/ test/media_centaur_web/page_smoke_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur_web/live/social_live.ex lib/media_centaur_web/live/social_live test/media_centaur_web
git commit -m "feat(social): hide a person; a member's card; copy names the relay rule"
```

---

### Task 11: Docs in the app repo

**Files:**
- Modify: `docs/social.md`, `docs/GLOSSARY.md`, `lib/media_centaur/topics.ex`
- Modify (wiki, sibling repo `../media-centaur.wiki`): `Social.md`, `Settings-Reference.md`, `Hosting-a-Private-Relay.md`

- [ ] **Step 1: `docs/social.md`**

Contexts table, the `MediaCentaur.Social` row becomes: "The network's *configuration* and who is on it: `Identity` (the keypair), `Relay` (`relays` table, each under the reader's **follow rule**: members or added), `Contact` (`contacts` table: one row per key the reader has a view of — a friend when `added_at` is set — with the reader's overrides and `hidden`), `RelayMember` (`relay_members`: the keys seen publishing on a members-rule relay, rebuilt per connect), `Connections`, `Profile`, and `Person`, built by `Social.people/0` for every followed key (ADR-074)."

Sync section: step 1 "subscribe `"feed"` (authors = friends ++ self on an added-rule relay; no author list on a members-rule relay, which restricts the read to its members itself; kinds 32164, 32161, 32163, 5 and 12160, `limit` 500, no `since`)"; step 2 begins "`Social.note_member/2` first — on a members-rule relay the author becomes followed by being served — then by kind: …"; new step after 3: "When a read completes (the first short page) → `Social.sweep_members/2` with the connect time: members the relay no longer serves are forgotten, with their profiles unless followed another way."; step 5 "A roster change or a relay's follow rule change on `social:updates` resubscribes …". The paragraph "Both ingest paths reject anything not signed by …" becomes "… not signed by a followed key (`Social.followed_key?/1`: the identity, a friend, or a member of a members-rule relay), so a relay that hands over the whole world still yields only what you follow — and on a members-rule relay, what you follow is everyone it serves."

PubSub table row for `social:updates`: add `{:relay_changed, _}`, `{:members_changed, _}`; `{:friend_changed, _}` → `{:contact_changed, _}`.

Web layer, Friends: after the foot's description add "**Hide** (`Social.set_hidden/2`, the `set_hidden` event with `hide`) keeps the person's activity off every surface; hidden people form the tab's hidden group (`Components.Social.HiddenPersonRow`, **Show**). A member followed through a members-rule relay has a card like a friend's; its foot says *on <host>* and carries no Remove friend."

- [ ] **Step 2: `lib/media_centaur/topics.ex`** — the `social:updates` row: `{:identity_changed, _}`, `{:relay_added, _}`, `{:relay_changed, _}`, `{:relay_removed, _}`, `{:friend_added, _}`, `{:contact_changed, _}`, `{:friend_removed, _}`, `{:members_changed, _}`, `{:profile_updated, _}`.

- [ ] **Step 3: `docs/GLOSSARY.md`**, Social table: replace the **Friend** and **Relay** rows and add four:

| Term | Meaning |
|---|---|
| **Follow rule** | The reader's choice, per relay, of who on it they follow (`Social.Relay.follow`): **members** — everyone who publishes on it, shown as *Everyone on this relay*, for a friend group's own allowlist relay — or **added** — only the keys the reader added by hand, *Only people I add*, the default, for any larger or public relay. Chosen on the add form and each relay row under Settings → Social → Relays (`Social.set_follow/2`). |
| **Contact** | One row per public key the reader has a view of (`Social.Contact`, `contacts` table): the reader's name, picture switch, colour and `hidden` for the key, and `added_at` when they added it by hand. A key is followed while it is a friend or a member of a members-rule relay; a row that is neither keeps the reader's choices for a return. |
| **Friend** | A contact the reader added by hand (`Social.Contact.added_at` set; `Social.add_friend/2`, `remove_friend/1`, `list_friends/0`). The **Friends** tab at `/social/friends` shows every followed person, friend or member. Never the name of the subsystem. |
| **Member** | A key seen publishing on a relay whose follow rule is members (`Social.RelayMember`, `relay_members`): observed by `RelaySync` (`Social.note_member/2`), never configured; forgotten when a read completes without it (`Social.sweep_members/2`), when the relay goes or its rule becomes added. On the relay side, a member is a key on the allowlist. |
| **Followed key** | The identity, a friend, or a member of a members-rule relay: `Social.followed_key?/1`, the one gate both ingest paths use. |
| **Hidden** | The reader's switch on a contact (`Social.set_hidden/2`, **Hide** on the opened card): the person's activity makes no feed row, glyph or rail card and their card leaves the grid for the tab's hidden group, where **Show** reverses it. Their profile is still ingested. The reader's alone; nothing on the wire. |
| **Relay** | A Nostr WebSocket server the user has configured (`Social.Relay`, `relays` table) under a follow rule. A **private relay** is one a friend group hosts with a pubkey allowlist (the `social-relay` repo); a **public relay** is anyone's. The app treats them alike on the wire; the follow rule is where they differ. |

- [ ] **Step 4: Wiki** (`cd ~/src/media-centaur/media-centaur.wiki`)

`Social.md`:
- The relay bullet (line 12) gains: "When you add a relay you choose who to follow on it: **Everyone on this relay**, for your group's own relay, or **Only people I add** (the default), for anything larger. Change it on the relay's row later."
- The friend bullet (line 14): "A **friend** is a public key you added by hand. On a relay set to **Everyone on this relay**, every member is on your Friends tab without adding them. Either way you see them under the name they publish …" and the last sentence becomes "You only read activity from people you follow — your friends, and everyone on a relay set to Everyone on this relay — and only from the relays you configured; anything else that arrives is discarded."
- Setup step 3: "… press **Add relay**. For your group's own relay choose **Everyone on this relay** first; the Friends tab fills on its own. The row shows **Connected** once the relay accepts you."
- Setup step 4 starts: "On a relay set to Only people I add, open **Social → Friends**, paste …"
- Friends section, the opened card's foot sentence: after "the friend's key, when you added them" → "the key, then *added* and the date for a friend, or *on* the relay for someone you follow through a relay set to Everyone on this relay; **Hide**, which takes their activity off every page (their card moves to **Hidden** at the end of the tab, where **Show** brings it back); and **Remove friend**, for a friend." Add: "Hiding someone is yours alone; they are not told."
- Line 120 "Activity from someone no longer on your Friends list shows nowhere." → "Activity from someone you removed or hid shows nowhere."

`Settings-Reference.md`, the **Relays** bullet: after "**Add relay** takes a `wss://` or `ws://` address" add "and who to follow on it — **Only people I add** (the default) or **Everyone on this relay**, for your group's own relay; each row's select changes it later. Switching a relay from Everyone to Only people I add drops the people you followed only through it."

`Hosting-a-Private-Relay.md`:
- Line 35: "… The row reads **Connected** once the relay has accepted their key. Tell them to choose **Everyone on this relay** when they add it: every member then sees every other without adding anyone."
- Line 62: "A removed member's activity is deleted from the relay when you remove them (social-relay v0.8.0 or later; an older relay keeps it). Their Media Centaur republishes it if you add them back."

Commit the wiki: `git add -A && git commit -m "wiki: relay follow rule, hidden people" && git push`.

- [ ] **Step 5: Commit the app docs**

```bash
git add docs/social.md docs/GLOSSARY.md lib/media_centaur/topics.ex
git commit -m "docs: relay follow rule, contacts, members, hidden"
```

---

### Task 12: Relay repository — forget a removed member's events

Work in `~/src/media-centaur/social-relay`.

**Files:**
- Modify: `internal/relay/membership.go`, `internal/relay/management.go`, `internal/relay/relay.go`
- Test: `internal/relay/management_test.go`
- Modify: `docs/protocol.md`, `docs/operating.md`

- [ ] **Step 1: Write the failing test**

In `management_test.go`:

```go
func TestUnallowedKeysStoredEventsAreNoLongerServed(t *testing.T) {
	admin, friend := nostr.Generate(), nostr.Generate()
	url := startRelay(t, admin.Public())
	m := manager(t, url, admin)
	if err := m.Allow(ctx(t), friend.Public(), ""); err != nil {
		t.Fatalf("allow: %v", err)
	}
	evt := review(t, friend, "tmdb:movie:1", nostr.Now())
	mustPublish(t, connectAs(t, url, friend), evt)
	if got := storedEvents(t, connectAs(t, url, admin), feedFilter(friend.Public())); len(got) != 1 {
		t.Fatalf("before unallow: got %d events, want 1", len(got))
	}

	if err := m.Unallow(ctx(t), friend.Public(), "left the group"); err != nil {
		t.Fatalf("unallow: %v", err)
	}

	if got := storedEvents(t, connectAs(t, url, admin), feedFilter(friend.Public())); len(got) != 0 {
		t.Fatalf("after unallow: got %d events from a removed member, want none", len(got))
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test ./internal/relay/ -run TestUnallowedKeysStoredEventsAreNoLongerServed`
Expected: FAIL — "after unallow: got 1 events".

- [ ] **Step 3: Implement**

`membership.go` (imports `fiatjaf.com/nostr/eventstore/boltdb` and `maps`):

```go
// forgetEvents deletes every stored event the key signed — activities, tombstones
// and profile — in pages of maxQueryLimit. A removed member's records are not
// served to the group; allowing the key again restores them, since its Media
// Centaur republishes whatever a relay lacks on its next connect.
func forgetEvents(store *boltdb.BoltBackend, pk nostr.PubKey) error {
	filter := nostr.Filter{Authors: []nostr.PubKey{pk}, Kinds: slices.Collect(maps.Keys(acceptedKinds))}
	for {
		var ids []nostr.ID
		for evt := range store.QueryEvents(filter, maxQueryLimit) {
			ids = append(ids, evt.ID)
		}
		if len(ids) == 0 {
			return nil
		}
		for _, id := range ids {
			if err := store.DeleteEvent(id); err != nil {
				return fmt.Errorf("delete %s: %w", id.Hex(), err)
			}
		}
	}
}
```

(`slices` and `maps` from the standard library; if `acceptedKinds` iteration order matters to the store's query planner it does not matter here.)

`management.go`: `managementAPI(m *membership, store *boltdb.BoltBackend, logger *log.Logger)`; the `UnallowPubKey` body becomes:

```go
			if err := m.unallow(pk); err != nil {
				return err
			}
			if err := forgetEvents(store, pk); err != nil {
				return fmt.Errorf("unallowed %s but could not forget its events: %w", nip19.EncodeNpub(pk), err)
			}
			logger.Printf("unallowed %s (%s); its events are forgotten", nip19.EncodeNpub(pk), reason)
			return nil
```

`relay.go`: `rl.ManagementAPI = managementAPI(members, store, rl.Log)`.

- [ ] **Step 4: Run the gate**

Run: `scripts/check`
Expected: green.

- [ ] **Step 5: Docs**

`docs/protocol.md`, the `unallowpubkey` row: "The key stops being a member at once: its next `REQ` and `EVENT` are `restricted:`, live events are no longer delivered to its open subscriptions, and every stored event it signed is deleted, so members stop reading it on their next request. Allowing the key again does not restore them; the key's Media Centaur republishes them on its next connect. Unallowing an admin is an error; admins are set in the config file."

`docs/operating.md` line 128's last sentence: "Their stored events are deleted when they are removed; if they are allowed again, their Media Centaur republishes them on its next connect."

- [ ] **Step 6: Commit and tag**

```bash
git add -A
git commit -m "feat: removing a member deletes the events it signed"
```

Tag `v0.8.0` per the repo's release steps once `scripts/check` is green and `main` is pushed.

---

### Task 13: Precommit and the spec's status

- [ ] **Step 1: Run the gate**

Run: `~/scripts/agents/agent-mix precommit`
Expected: green. Fix every warning, Credo finding (MC0009 wants a story for `settings_select` and `hidden_person_row`: Task 8 and Task 9 added them), format change and test failure it reports. A SQLite "Database busy" on one file: re-run that file alone.

- [ ] **Step 2: Mark the spec**

In `docs/superpowers/specs/2026-10-12-relay-follow-rule-design.md` change `Status: proposed, 2026-10-12.` to `Status: implemented (see docs/superpowers/plans/2026-10-12-relay-follow-rule.md).`

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-10-12-relay-follow-rule-design.md
git commit -m "docs: relay follow rule spec implemented"
```
