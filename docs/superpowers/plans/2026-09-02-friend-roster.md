# Friend Roster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The friend roster — the public keys whose recommendations this install reads, each with a local nickname — managed on the Friends tab.

**Architecture:** `Friends.Friend` (table `friends`: `pubkey` hex unique, `nickname` required) with `add_friend/2`, `remove_friend/1`, `list_friends/0`, `friend_by_pubkey/1`, `friend_pubkeys/0`; typed events `FriendAdded`/`FriendRemoved` on `friends:updates` (the recommendations sync in layer 6 resubscribes on them). A roster block on the Friends tab beside the identity and relay blocks. Same shape as the relay list (layer 4, Task 2/4) — mirror it.

**Spec:** `docs/superpowers/specs/2026-09-02-friends-recommendations-design.md` — decision 6 (friend = pasted npub + local nickname; no profile events), Architecture › `Friends.Friend`, UI › Friends tab › Friends block. Layer 5.

**Decisions fixed by this plan:**
- Input accepts an npub or 64-hex; stored as lowercase hex via `Nostr.Keys.parse_pubkey/1`. Nickname is trimmed and required.
- Adding your own key is refused (flash **"That is your own key"**). Re-adding an existing key updates the nickname (idempotent by pubkey).
- Removing a friend needs no confirmation (trivially reversible; MC0027 treatment (a)).
- Copy (house voice): heading **Friends**; body **"People whose recommendations you read. Add a friend with the key they give you; the name is only for you."**; inputs: key placeholder `npub1…`, name placeholder `Name`; button **Add friend**; errors: **"That is not a valid public key"**, **"Give your friend a name"**; row shows the nickname and a shortened npub (`npub1abcd…wxyz`, first 9 + last 4 chars), action **Remove**.

**House rules:** test-first; zero warnings; `mix format`; credo custom checks (MC0003, MC0024, MC0025, MC0027, event chokepoint); no real names in fixtures ("Sample Friend"); commits end with `Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz`, never `Co-Authored-By`; no push, no tag.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Create | `priv/repo/migrations/20260902170000_add_friends.exs` | `friends` table |
| Create | `lib/media_centaur/friends/friend.ex` | schema |
| Modify | `lib/media_centaur/friends.ex`, `lib/media_centaur/friends/events.ex` | CRUD + events |
| Create | `test/media_centaur/friends/friend_test.exs` | |
| Create | `lib/media_centaur_web/live/discovery_live/roster_block.ex` | roster block |
| Modify | `lib/media_centaur_web/live/discovery_live.ex`, `test/media_centaur_web/live/discovery_live_test.exs` | |

---

### Task 1: `Friends.Friend` + events

- [ ] **Step 1: Failing tests** — `test/media_centaur/friends/friend_test.exs`:

```elixir
defmodule MediaCentaur.Friends.FriendTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Events.{FriendAdded, FriendRemoved}
  alias MediaCentaur.Friends.{Friend, Identity}
  alias MediaCentaur.Nostr.Keys

  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  describe "add_friend/2" do
    test "accepts an npub, stores lowercase hex + trimmed nickname, broadcasts" do
      Friends.subscribe()
      npub = Keys.to_npub(@pubkey)
      assert {:ok, %Friend{pubkey: @pubkey, nickname: "Sample Friend"}} = Friends.add_friend(npub, "  Sample Friend ")
      assert_receive {:friend_added, %FriendAdded{pubkey: @pubkey}}, 500
      assert [%Friend{pubkey: @pubkey}] = Friends.list_friends()
      assert Friends.friend_pubkeys() == [@pubkey]
    end

    test "accepts hex in any case and re-adding updates the nickname" do
      {:ok, a} = Friends.add_friend(String.upcase(@pubkey), "One")
      {:ok, b} = Friends.add_friend(@pubkey, "Two")
      assert a.id == b.id
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
      {:ok, _} = Friends.add_friend(@pubkey, "Sample Friend")
      Friends.subscribe()
      assert :ok = Friends.remove_friend(@pubkey)
      assert_receive {:friend_removed, %FriendRemoved{pubkey: @pubkey}}, 500
      assert Friends.list_friends() == []
      assert :ok = Friends.remove_friend(@pubkey)
      refute_receive {:friend_removed, _}, 100
    end
  end
end
```

- [ ] **Step 2: Migration** `20260902170000_add_friends.exs`: table `friends` (`id :uuid` pk, `pubkey :text null: false`, `nickname :text null: false`, `timestamps(type: :utc_datetime)`), `create unique_index(:friends, [:pubkey])`.

- [ ] **Step 3: Schema** `lib/media_centaur/friends/friend.ex`:

```elixir
defmodule MediaCentaur.Friends.Friend do
  @moduledoc "A followed public key (lowercase hex) with the nickname this install gave it."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "friends" do
    field :pubkey, :string
    field :nickname, :string
    timestamps()
  end

  @type t :: %__MODULE__{}

  def changeset(friend \\ %__MODULE__{}, attrs) do
    friend
    |> cast(attrs, [:pubkey, :nickname])
    |> update_change(:nickname, &String.trim/1)
    |> validate_required([:pubkey, :nickname])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint(:pubkey)
  end
end
```

- [ ] **Step 4: Context + events** — `friends/events.ex`: `FriendAdded{pubkey}` / `FriendRemoved{pubkey}` with `broadcast/1` clauses publishing `{:friend_added, e}` / `{:friend_removed, e}`. `friends.ex` (exports add `Friend, Events.FriendAdded, Events.FriendRemoved`):

```elixir
  @spec add_friend(String.t(), String.t()) ::
          {:ok, Friend.t()} | {:error, :invalid_pubkey | :nickname_required | :own_key | Ecto.Changeset.t()}
  def add_friend(key, nickname) when is_binary(key) and is_binary(nickname) do
    with {:ok, pubkey} <- Keys.parse_pubkey(String.trim(key)),
         :ok <- not_own_key(pubkey),
         :ok <- nickname_present(nickname) do
      upsert_friend(pubkey, String.trim(nickname))
    end
  end

  defp not_own_key(pubkey), do: if(Identity.pubkey() == pubkey, do: {:error, :own_key}, else: :ok)
  defp nickname_present(nickname), do: if(String.trim(nickname) == "", do: {:error, :nickname_required}, else: :ok)

  defp upsert_friend(pubkey, nickname) do
    case Repo.get_by(Friend, pubkey: pubkey) do
      %Friend{} = existing ->
        Repo.update(Friend.changeset(existing, %{nickname: nickname}))

      nil ->
        case Repo.insert(Friend.changeset(%{pubkey: pubkey, nickname: nickname})) do
          {:ok, friend} ->
            Events.broadcast(%Events.FriendAdded{pubkey: pubkey})
            {:ok, friend}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            if Enum.any?(errors, fn {_f, {_m, meta}} -> meta[:constraint] == :unique end),
              do: Repo.update(Friend.changeset(Repo.get_by!(Friend, pubkey: pubkey), %{nickname: nickname})),
              else: {:error, changeset}
        end
    end
  end

  @spec remove_friend(String.t()) :: :ok
  def remove_friend(pubkey) do
    case Repo.get_by(Friend, pubkey: String.downcase(pubkey)) do
      nil -> :ok
      friend ->
        Repo.delete!(friend)
        Events.broadcast(%Events.FriendRemoved{pubkey: friend.pubkey})
        :ok
    end
  end

  @spec list_friends() :: [Friend.t()]
  def list_friends, do: Repo.all(from(f in Friend, order_by: f.nickname))

  @spec friend_by_pubkey(String.t()) :: Friend.t() | nil
  def friend_by_pubkey(pubkey), do: Repo.get_by(Friend, pubkey: pubkey)

  @doc "Every followed pubkey — the authors the feed subscribes to."
  @spec friend_pubkeys() :: [String.t()]
  def friend_pubkeys, do: Repo.all(from(f in Friend, select: f.pubkey, order_by: f.pubkey))
```

(Alias `Keys` from `MediaCentaur.Nostr`; `Identity` is in this context.)

- [ ] **Step 5:** `mix test test/media_centaur/friends && mix compile --warnings-as-errors && mix format && mix credo --strict`; `mix ecto.migrate` on the dev DB. Commit `feat(friends): Friend — the roster of followed keys with local nicknames`.

---

### Task 2: Roster block on the Friends tab

- [ ] **Step 1: Failing tests** (in the `friends tab` describe of `discovery_live_test.exs`):

```elixir
    test "adds a friend by npub + name, lists them, and removes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      npub = Keys.to_npub("f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9")

      view |> form("#add-friend-form", %{"key" => npub, "nickname" => "Sample Friend"}) |> render_submit()
      assert has_element?(view, "#friend-f9308a01", "Sample Friend")
      assert has_element?(view, "#friend-f9308a01", "npub1lyn6f…" <> String.slice(npub, -4..-1//1))
      assert [%{nickname: "Sample Friend"}] = Friends.list_friends()

      view |> element("#friend-f9308a01 button", "Remove") |> render_click()
      refute has_element?(view, "#friend-f9308a01")
      assert Friends.list_friends() == []
    end

    test "refuses a bad key, a blank name, and your own key with flashes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")

      view |> form("#add-friend-form", %{"key" => "npub1nope", "nickname" => "X"}) |> render_submit()
      assert render(view) =~ "That is not a valid public key"

      view |> form("#add-friend-form", %{"key" => Identity.npub(), "nickname" => "Me"}) |> render_submit()
      assert render(view) =~ "That is your own key"

      view |> form("#add-friend-form", %{"key" => Keys.to_npub("f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"), "nickname" => " "}) |> render_submit()
      assert render(view) =~ "Give your friend a name"
      assert Friends.list_friends() == []
    end
```

The shortened-npub assertion: compute the expected string with the same helper the component exposes (`RosterBlock.short_npub/1`) rather than a literal prefix — replace the literal with `RosterBlock.short_npub(npub)`. The row id is `"friend-" <> String.slice(pubkey, 0, 8)`.

- [ ] **Step 2: LiveView** — `handle_params` for `:friends` also assigns `friends: Friends.list_friends()`; events `"add_friend"` (`%{"key" => key, "nickname" => nickname}`) → `Friends.add_friend/2`: `{:ok, _}` reload + no flash; `{:error, :invalid_pubkey}` → flash "That is not a valid public key"; `{:error, :nickname_required}` → "Give your friend a name"; `{:error, :own_key}` → "That is your own key"; `{:error, %Ecto.Changeset{}}` → "That is not a valid public key". `"remove_friend"` (`%{"pubkey" => pubkey}`) → `Friends.remove_friend/1` + reload. `handle_info({:friend_added, _} | {:friend_removed, _}, socket)` → reload when on `:friends`.

- [ ] **Step 3: Component** `lib/media_centaur_web/live/discovery_live/roster_block.ex` — same layout vocabulary as `RelayBlock`: heading, body copy, `<ul>` of rows (`id={"friend-" <> String.slice(friend.pubkey, 0, 8)}`: nickname `text-sm font-medium`, `<code>` short npub `text-xs text-base-content/50`, Remove button `phx-click="remove_friend" phx-value-pubkey={friend.pubkey}`), and `<form id="add-friend-form" phx-submit="add_friend">` with two inputs (`name="key"` placeholder `npub1…`, `name="nickname"` placeholder `Name`) and **Add friend**. Public `short_npub/1`: `npub = Keys.to_npub(pubkey); String.slice(npub, 0, 9) <> "…" <> String.slice(npub, -4..-1//1)`. `attr :friends, :list, required: true, doc: "\`Friend.t()\` by nickname"`.

- [ ] **Step 4:** `mix format && mix compile --warnings-as-errors && mix test test/media_centaur_web/live/discovery_live_test.exs && mix credo --strict && mix boundaries`; `page-shot` of `/discovery/friends`. Commit `feat(discovery): roster block on the Friends tab`.

---

### Task 3: Precommit + campaign

- [ ] `mix precommit` PASSED.
- [ ] `campaigns/friends-recommendations.md` Status: "Layer 5 (roster: `Friends.Friend`, roster block) landed 2026-09-02; next: layer 6 (`Recommendations`: schema, translation, sync, recommend modal, Feed tab)."
- [ ] Commit `docs(campaign): friend roster landed; next = recommendations`.

---

## Self-review

**Spec coverage:** decision 6 and the `Friends.Friend` API (`add_friend/1` in the spec takes "an npub or hex plus nickname" → `add_friend/2` here; `remove_friend/1`; `list_friends/0`; `friend_by_pubkey/1`) → Task 1; the Friends tab roster block (nickname + shortened npub, add by npub + nickname, remove) → Task 2; `friend_pubkeys/0` for the layer-6 subscription → Task 1.

**Type consistency:** `Friends.add_friend/2`, `remove_friend/1`, `list_friends/0`, `friend_by_pubkey/1`, `friend_pubkeys/0`; events `{:friend_added, %FriendAdded{pubkey}}` / `{:friend_removed, %FriendRemoved{pubkey}}`; LiveView events `add_friend` (`key`, `nickname`) / `remove_friend` (`pubkey`); `RosterBlock.short_npub/1`; row id `friend-<8 hex>`.

**Placeholders:** none.
