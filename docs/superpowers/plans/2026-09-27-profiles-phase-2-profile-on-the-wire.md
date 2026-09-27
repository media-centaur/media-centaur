# Profiles, phase 2: the profile on the wire. Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person publishes a name; friends see it. Kind 12160 on the wire, one `Social.Profile` per known key, the sync loop moved to `RelaySync` above both contexts, Settings opening on Your profile whose save mints the identity, and then the phase-1 openings: the `friends` rebuild, the optional local name, Unnamed, the person glyph.

**Architecture:** `Social.Profile` (schema) and `Social.Profile.Translation` (pure, kind 12160) live in Social, which owns saving the reader's own profile, ingesting a friend's, the own event for the diff, and pruning. `MediaCentaur.RelaySync` (deps Activities, Social, Nostr) is the moved `Activities.Sync`: its kinds are both contexts' lists, its ingest dispatches by kind, its own-events diff concatenates both contexts' own events, and its refusal words come from whichever context owns the event. `Social.people/0` joins profiles into `Person.published_name`; `Person.name/1` resolves; `Format.person_name/1` says Unnamed. The relay stores 12160 as a replaceable record keyed by signer and kind. Two shared rules move to their owners: `Nostr.Event.stamp_after/2` (strictly after the stored record) and `Social.known_key?/1` (the identity or the roster).

**Tech Stack:** Elixir 1.20 / Phoenix LiveView, Ecto + `ecto_sqlite3`, Phoenix Storybook, ExUnit + LazyHTML + `FakeRelay`; Go (khatru) in `../social-relay`.

**Design:** `docs/superpowers/specs/2026-09-27-profiles-design.md` §§ On the wire, The relay, Storage, The Person read model, Identity minting, Settings → Social, Friends, Events, Contexts. ADR-073, ADR-074, UIDR-047. Campaign: `campaigns/profiles.md` (§ Follow-ups from phase 1 reviews is this phase's opening list). Unify pass 2026-09-27: the relay's slot must find a replaceable record by signer and kind; the sync loop moves; `known_key?` and `stamp_after` move to their owners.

---

## Read before starting

- **Never run `mix` directly.** Every app command is `~/scripts/agents/agent-mix …`. The dev daily driver compiles into this checkout's `_build/dev`; a bare `mix` takes it down. The relay is Go: its commands are `scripts/check` and `go test ./...` inside `../social-relay`.
- **Test first**, red then green, per task.
- **The suite stays green between tasks** in this phase, except inside Task 5 (the move) and Task 7 (the rebuild), each of which is green at its commit. Work on `main` in both repos, commit per task, push nothing. **The relay's v0.7.0 tag and push wait for the owner's ship instruction**; the app develops against the dev relay, which `just social-up` builds from the relay's working tree.
- **Commit messages**: conventional, plain prose body, the session's attribution trailer the harness gives you, never `Co-Authored-By`.
- **Copy**: every new user-facing string (the Settings card's title, description, labels, button, flashes; the add-friend hint; "Unnamed") goes through the `writing-copy` skill before its task's commit. The strings here are working versions.
- **Storybook**: MC0009; story filenames are pinned to the component function.
- **Zero warnings.** `mix_unused` runs in precommit: every public function added here gains a caller in this phase.
- **Migrations**: the paired rule. The `friends` rebuild keeps `nickname` nullable for the outgoing release; the release after this one drops it (campaign). MC0015 forbids row mutation in a schema migration; the rebuild's `INSERT … SELECT` is the table copy and carries the same per-line disable the `DropWatchlistFlatColumns` migration used, if Credo reports it.
- **Wire caps live in one place**: `Social.Profile.Translation`. The protocol page (Task 9) mirrors them.
- `Library.Person` exists (a cast member). `Social.Person` is the read model; alias `as: SocialPerson` where both are in scope.

## What this phase does not do, on purpose

- No avatar: no `avatar` field on the wire, no upload, no file store, no `show_avatar` column or switch. Phase 3. `Person.avatar_url` stays nil.
- No `Social.person/1` (no caller).
- No profile deletion (ADR-073: never withdrawn). Removing a friend deletes their stored row; replacing the identity deletes the old own row.
- `nickname` is not dropped; the release after this one drops it.

## File structure

Created (app):

- `priv/repo/migrations/<stamp>_create_profiles.exs`, `priv/repo/migrations/<stamp>_friends_name_override_is_optional.exs`
- `lib/media_centaur/social/profile.ex`, `lib/media_centaur/social/profile/translation.ex`
- `lib/media_centaur/relay_sync.ex` (moved from `lib/media_centaur/activities/sync.ex`)
- `test/media_centaur/social/profile_translation_test.exs`, `test/media_centaur/social/profile_test.exs`, `test/media_centaur/relay_sync_test.exs` (moved from `test/media_centaur/activities/sync_test.exs`)

Modified (app): `lib/media_centaur/nostr/event.ex`, `lib/media_centaur/activities.ex`, `lib/media_centaur/social.ex`, `lib/media_centaur/social/events.ex`, `lib/media_centaur/social/identity.ex`, `lib/media_centaur/social/person.ex`, `lib/media_centaur/social/friend.ex`, `lib/media_centaur/format.ex`, `lib/media_centaur/application.ex`, `lib/media_centaur/log/component.ex`, `lib/media_centaur/topics.ex`, `lib/media_centaur_web/live/settings_live.ex`, `lib/media_centaur_web/live/settings_live/social_section.ex`, `lib/media_centaur_web/live/discovery_live.ex`, `lib/media_centaur_web/live/discovery_live/add_friend_block.ex`, `lib/media_centaur_web/components/discovery/identity_tile.ex`, `lib/media_centaur_web/components/discovery/person_card.ex`, `test/support/discovery_rows.ex`, `test/support/global_state_sandbox.ex`, stories (`identity_tile`, `person_card`, `feed_row`), tests named per task, `docs/social-protocol.md`, `docs/social.md`, `docs/GLOSSARY.md`, `campaigns/profiles.md`, wiki pages.

Relay (`../social-relay`): `internal/relay/kinds.go`, `internal/relay/slot.go`, `internal/relay/kinds_test.go`, `internal/relay/relay_test.go`, `internal/relay/deletion_test.go`, `docs/protocol.md`, `docs/operating.md`, `README.md`, `decisions/003-replaceable-kinds-in-the-slot.md`.

---

### Task 1: The relay stores kind 12160 as a replaceable record

**Repo:** `/home/shawn/src/media-centaur/social-relay` (Go, khatru). Read `CLAUDE.md`, `docs/protocol.md`, `decisions/002-address-slot-in-relay.md`, `internal/relay/kinds.go`, `internal/relay/slot.go`, `internal/relay/relay.go` and the three test files first.

Today the slot finds a record by its `d` tag (`slot.go` `read`), and bolt never indexes an empty tag value, so a replaceable event (no `d`) would be stored beside every earlier one and never replace it. khatru already routes every non-regular kind to `ReplaceEvent` → `storeActivity`, so 12160 reaches the slot; only the lookup is wrong. Deletions parse their `a` tag through `parseAddress`, which admits activity kinds only; a profile stays undeletable by keeping 12160 out of `activityKinds`.

- [ ] **Step 1: Tests first**

In `internal/relay/kinds_test.go`, beside `signedKind`, add a helper for a replaceable event with no `d` tag, and three tests. Adapt the helper names to the file's (`startRelay`, `connectAs`, `mustPublish`, `storedEvents`, `publish`, `request`, `readEvent` exist per the current tests; read them):

```go
// signedProfile signs a kind 12160 with no d tag and the given created_at and content.
func signedProfile(t *testing.T, sk nostr.SecretKey, createdAt nostr.Timestamp, content string) nostr.Event {
	t.Helper()
	evt := nostr.Event{Kind: 12160, CreatedAt: createdAt, Content: content, Tags: nostr.Tags{}}
	if err := evt.Sign(sk); err != nil {
		t.Fatal(err)
	}
	return evt
}

func TestProfileIsAccepted(t *testing.T) {
	r, sk := startRelay(t)
	ws := connectAs(t, r, sk)
	mustPublish(t, ws, signedProfile(t, sk, 1_700_000_000, `{"v":1,"name":"Sample"}`))
	got := storedEvents(t, ws, nostr.Filter{Kinds: []nostr.Kind{12160}})
	if len(got) != 1 {
		t.Fatalf("stored %d profiles, want 1", len(got))
	}
}

func TestNewerProfileReplacesOlderAndTheStoredOneKeepsATie(t *testing.T) {
	r, sk := startRelay(t)
	ws := connectAs(t, r, sk)
	mustPublish(t, ws, signedProfile(t, sk, 1_700_000_000, `{"v":1,"name":"One"}`))
	mustPublish(t, ws, signedProfile(t, sk, 1_700_000_010, `{"v":1,"name":"Two"}`))
	mustPublish(t, ws, signedProfile(t, sk, 1_700_000_010, `{"v":1,"name":"Tie"}`))
	got := storedEvents(t, ws, nostr.Filter{Kinds: []nostr.Kind{12160}})
	if len(got) != 1 || got[0].Content != `{"v":1,"name":"Two"}` {
		t.Fatalf("stored %v, want the single newer profile", got)
	}
}

func TestDeletionCannotNameAProfile(t *testing.T) {
	r, sk := startRelay(t)
	ws := connectAs(t, r, sk)
	mustPublish(t, ws, signedProfile(t, sk, 1_700_000_000, `{"v":1}`))
	del := deletion(t, sk, "12160:"+sk.Public().Hex()+":", 1_700_000_100) // adapt to deletion_test.go's helper signature
	ok, reason := publish(t, ws, del)
	if ok || reason != "blocked: only the author may delete an event" {
		t.Fatalf("deletion of a profile answered %v %q", ok, reason)
	}
}
```

If `startRelay` returns differently or `publish` reports the `OK` differently, follow the file. Run: `go test ./internal/relay/ -run 'Profile|Deletion' -v` from the relay root. Expected: `TestProfileIsAccepted` fails with `blocked: kind 12160 is not stored by this relay`; the other two fail after it.

- [ ] **Step 2: kinds.go**

Add after `kindDeletion`:

```go
// kindProfile is a person's published self-description: replaceable, one record
// per signer, no `d` tag, never deleted (a kind 5 may name activity kinds only).
const kindProfile nostr.Kind = 12160

// replaceableKinds is the single place to widen what the relay stores as one
// record per signer per kind. They share the slot with the activity kinds; their
// address has an empty `d`.
var replaceableKinds = map[nostr.Kind]struct{}{
	kindProfile: {},
}
```

Make `acceptedKinds` include them:

```go
var acceptedKinds = func() map[nostr.Kind]struct{} {
	m := map[nostr.Kind]struct{}{kindDeletion: {}}
	for k := range activityKinds {
		m[k] = struct{}{}
	}
	for k := range replaceableKinds {
		m[k] = struct{}{}
	}
	return m
}()
```

Reword the file comment at the top (lines 10–15 today) to: "The relay stores three addressable activity kinds (one record per signer per kind per `d` tag), one replaceable kind (one record per signer per kind, no `d`), and kind 5 deletions naming an activity. It never interprets content; the shapes are the app's contract (docs/protocol.md). 32160 and 32162 are retired: never reused, refused with `blocked:`." Leave `parseAddress` and `deletionAddress` alone: they admit activity kinds only, which is the rule.

- [ ] **Step 3: slot.go**

`read` finds a replaceable record without the `d` clause and looks for no deletion:

```go
// read returns what a holds: at most one record and, for an activity kind, one
// deletion. A replaceable kind's record is found by signer and kind alone: it has
// no d tag, and the store never indexes an empty tag value.
func (s *slot) read(a address) (rec, del *nostr.Event) {
	recFilter := nostr.Filter{Kinds: []nostr.Kind{a.kind}, Authors: []nostr.PubKey{a.pubkey}}
	if !a.kind.IsReplaceable() {
		recFilter.Tags = nostr.TagMap{"d": []string{a.d}}
	}
	rec = s.one(recFilter)
	if a.kind.IsReplaceable() {
		return rec, nil
	}
	del = s.one(nostr.Filter{
		Kinds: []nostr.Kind{kindDeletion}, Authors: []nostr.PubKey{a.pubkey},
		Tags: nostr.TagMap{"a": []string{a.String()}},
	})
	return rec, del
}
```

`storeActivity` needs no change: `evt.Tags.GetD()` is `""` for a profile, `del` is nil, the newer-wins and tie rules are the same. Rename it `storeRecord` and update its comment ("applies an activity or a replaceable kind") and the `ReplaceEvent` wiring in `relay.go`, so the name no longer lies. Update the `slot` type comment: "one record per address: a signer's activity or the deletion that withdrew it, or a signer's replaceable record."

Run: `go test ./internal/relay/ -v` then `scripts/check`. Expected: every test passes, including the three new ones. If `nostr.Kind` has no `IsReplaceable` method in the vendored khatru, use `10000 <= a.kind && a.kind < 20000`.

- [ ] **Step 4: Docs and the record**

`docs/protocol.md`: line 3 lists the stored kinds; add "a profile, kind 12160, replaceable: one record per signer, no `d`". Line 54 (the rejection row) becomes "Kind other than `32164`, `32161`, `32163`, `12160` or `5`". Line 59 (the slot): add "A replaceable kind's address is `<kind>:<pubkey>:` and holds one record per signer; a kind 5 may not name it." `README.md:3`: add 12160 to the stored kinds. `docs/operating.md:31`: fix the stale `supported_nips` to `[1,9,11,42,86]`.

Create `decisions/003-replaceable-kinds-in-the-slot.md`:

```markdown
---
status: accepted
date: 2026-09-27
---
# Replaceable kinds share the slot, keyed by signer and kind; only activity kinds are deletable

Extends ADR-002.

## Context and Problem Statement

The app's contract gains a profile (kind 12160): replaceable, one record per signer, no `d` tag, never withdrawn. The slot found a record by its `d` tag, and the bbolt backend never indexes an empty tag value, so a replaceable event would be stored beside every earlier one and never replace it. A kind 5 must not be able to name a profile.

## Decision Outcome

Chosen option: the slot's `read` finds a replaceable kind's record by signer and kind alone and looks for no deletion; the newer-wins and tie rules are unchanged. "Stored" and "deletable" are two sets: `acceptedKinds` gains `replaceableKinds`, while `parseAddress` keeps admitting activity kinds only, so a deletion naming `12160:<pubkey>:` is refused with the existing `blocked: only the author may delete an event`.

### Consequences

* Good, because one routine still decides every ordering rule, tie included.
* Good, because widening what the relay stores is one map per storage rule.
* Bad, because the deletion refusal for a profile reuses the author wording rather than saying "profiles are not deletable"; the app never sends one.
```

- [ ] **Step 5: Commit (relay repo), no tag, no push**

```bash
cd /home/shawn/src/media-centaur/social-relay
scripts/check
git add -A
git commit -m "feat: store a profile (kind 12160) as one replaceable record per signer; a deletion may not name it"
```

Report the commit SHA. Then, from the app repo, rebuild and restart the dev relay so the app can talk to it: `just social-up` (it builds `social-relay:dev` from the relay's working tree). Report its output.

---

### Task 2: Two shared rules move to their owners

**Files:**
- Modify: `lib/media_centaur/nostr/event.ex` (after `new/1`)
- Modify: `lib/media_centaur/activities.ex:393-401` (`stamp/3`), `:449-453` (`known_author/1`)
- Modify: `lib/media_centaur/social.ex` (after `friend_pubkeys/0`)
- Test: `test/media_centaur/nostr/event_test.exs` (add), `test/media_centaur/social/friend_test.exs` (add), `test/media_centaur/activities/activities_test.exs` (unchanged, run)

- [ ] **Step 1: Tests**

In `test/media_centaur/nostr/event_test.exs` add:

```elixir
  describe "stamp_after/2" do
    test "a new record is stamped strictly after the one it replaces, and never before now" do
      assert Event.stamp_after(nil, 1_000) == 1_000
      assert Event.stamp_after(900, 1_000) == 1_000
      assert Event.stamp_after(1_000, 1_000) == 1_001
      assert Event.stamp_after(1_500, 1_000) == 1_501
    end
  end
```

In `test/media_centaur/social/friend_test.exs` add a describe:

```elixir
  describe "known_key?/1" do
    test "the identity and every roster key are known; anything else is not" do
      {:ok, _friend} = Social.add_friend(@pubkey, "Sample Friend")
      refute Social.known_key?(String.duplicate("a", 64))
      assert Social.known_key?(@pubkey)

      Identity.ensure()
      assert Social.known_key?(Identity.pubkey())
    end
  end
```

Run both files: red (`stamp_after/2` and `known_key?/1` undefined).

- [ ] **Step 2: `Nostr.Event.stamp_after/2`**

After `new/1` in `lib/media_centaur/nostr/event.ex`:

```elixir
  @doc """
  The wire time for a record that replaces `held` (the stored record's
  `created_at`, or nil): `now`, or one second past `held` when `now`
  does not already pass it. A relay keeps one record per address and,
  on a tie, keeps what it holds, so a replacement made within the same
  second must be stamped later or the relay discards it and the
  own-events diff republishes it on every connect.
  """
  @spec stamp_after(non_neg_integer() | nil, non_neg_integer()) :: non_neg_integer()
  def stamp_after(nil, now), do: now
  def stamp_after(held, now) when is_integer(held), do: max(now, held + 1)
```

- [ ] **Step 3: Activities adopts it**

Replace `stamp/3` in `lib/media_centaur/activities.ex`:

```elixir
  defp stamp(nil, now, _bound), do: now

  defp stamp(%Activity{} = activity, now, bound) do
    held = Enum.max([Activity.event_created_at(activity), Activity.deletion_created_at(activity) || 0])

    case bound do
      :after -> Event.stamp_after(held, now)
      :at_or_after -> max(now, held)
    end
  end
```

(Read the two call sites to confirm the second bound's atom; the deletion path uses the "no earlier than" bound. Keep its atom, whatever it is, and map it to `max(now, held)`.) Keep the comment above `stamp/3`; shorten it to point at `Event.stamp_after/2` for the rationale.

- [ ] **Step 4: `Social.known_key?/1`, Activities adopts it**

In `lib/media_centaur/social.ex` after `friend_pubkeys/0`:

```elixir
  @doc "Whether a public key is this identity's or on the roster: the keys whose events a reader keeps."
  @spec known_key?(String.t()) :: boolean()
  def known_key?(pubkey) when is_binary(pubkey),
    do: pubkey == Identity.pubkey() or friend_by_pubkey(pubkey) != nil
```

In `activities.ex` replace `known_author/1`:

```elixir
  defp known_author(pubkey),
    do: if(Social.known_key?(pubkey), do: :ok, else: {:error, :unknown_author})
```

- [ ] **Step 5: Green, commit**

Run: `~/scripts/agents/agent-mix test test/media_centaur/nostr/event_test.exs test/media_centaur/social/friend_test.exs test/media_centaur/activities/activities_test.exs`. Expected: PASS.

```bash
git add lib/media_centaur/nostr/event.ex lib/media_centaur/activities.ex lib/media_centaur/social.ex test/media_centaur/nostr/event_test.exs test/media_centaur/social/friend_test.exs
git commit -m "refactor: Event.stamp_after owns the strictly-after rule; Social.known_key? owns the known-key gate"
```

---

### Task 3: `Social.Profile`: the table, the translation, save, ingest, own events, pruning

**Files:**
- Create: `priv/repo/migrations/20260928100000_create_profiles.exs`
- Create: `lib/media_centaur/social/profile.ex`, `lib/media_centaur/social/profile/translation.ex`
- Modify: `lib/media_centaur/social.ex` (Boundary exports; new functions), `lib/media_centaur/social/events.ex`, `lib/media_centaur/social/identity.ex` (moduledoc only), `lib/media_centaur/topics.ex:61`
- Test: `test/media_centaur/social/profile_translation_test.exs`, `test/media_centaur/social/profile_test.exs`

- [ ] **Step 1: Translation tests**

```elixir
defmodule MediaCentaur.Social.Profile.TranslationTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Social.Profile.Translation

  @secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @pubkey Keys.pubkey(@secret)

  defp signed(content, created_at \\ 1_700_000_000) do
    Event.sign(
      Event.new(%{pubkey: @pubkey, created_at: created_at, kind: 12_160, tags: [], content: content}),
      @secret
    )
  end

  test "kind/0 is 12160, the first of the replaceable block" do
    assert Translation.kind() == 12_160
  end

  test "to_event/3 builds an unsigned profile with the name and version, no tags" do
    event = Translation.to_event("Sample Name", @pubkey, 1_700_000_000)

    assert %Event{kind: 12_160, tags: [], pubkey: @pubkey, created_at: 1_700_000_000} = event
    assert Jason.decode!(event.content) == %{"v" => 1, "name" => "Sample Name"}
  end

  test "to_event/3 leaves an absent name off the wire" do
    assert Jason.decode!(Translation.to_event(nil, @pubkey, 1).content) == %{"v" => 1}
  end

  test "from_event/1 reads the name, the raw event and the wire time; a missing name is nil" do
    event = signed(~s({"v":1,"name":"  Sample Name  "}))

    assert {:ok, %{pubkey: @pubkey, name: "Sample Name", created_at: 1_700_000_000, raw_event: raw}} =
             Translation.from_event(event)

    assert raw == Event.to_map(event)
    assert {:ok, %{name: nil}} = Translation.from_event(signed(~s({"v":1})))
    assert {:ok, %{name: nil}} = Translation.from_event(signed(~s({"v":1,"name":"   "})))
  end

  test "from_event/1 drops the malformed whole: wrong kind, bad JSON, a name over the cap, an unknown version" do
    other = Event.sign(Event.new(%{pubkey: @pubkey, created_at: 1, kind: 32_164, tags: [], content: "{}"}), @secret)
    assert {:error, :wrong_kind} = Translation.from_event(other)
    assert {:error, :bad_content} = Translation.from_event(signed("not json"))
    assert {:error, :bad_content} = Translation.from_event(signed(~s({"v":1,"name":"#{String.duplicate("x", 51)}"})))
    assert {:error, :bad_content} = Translation.from_event(signed(~s({"v":1,"name":7})))
    assert {:error, :unsupported_version} = Translation.from_event(signed(~s({"v":2,"name":"x"})))
  end

  test "an unknown field is ignored and a name at the cap passes" do
    name = String.duplicate("x", 50)
    assert {:ok, %{name: ^name}} = Translation.from_event(signed(~s({"v":1,"name":"#{name}","later":true})))
  end
end
```

Check `MediaCentaur.Secret.wrap/1` and `Keys.pubkey/1` spellings against `test/media_centaur/activities/activities_test.exs`'s friend fixtures and copy theirs if they differ.

- [ ] **Step 2: Profile tests**

```elixir
defmodule MediaCentaur.Social.ProfileTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Nostr.Event
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Social
  alias MediaCentaur.Social.Events.ProfileUpdated
  alias MediaCentaur.Social.Identity
  alias MediaCentaur.Social.Profile
  alias MediaCentaur.Social.Profile.Translation

  @friend_secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @friend_pubkey Keys.pubkey(@friend_secret)

  defp friend_profile(name, created_at),
    do: Event.sign(Translation.to_event(name, @friend_pubkey, created_at), @friend_secret)

  describe "save_profile/1" do
    test "mints the identity, stores the row, publishes, broadcasts; a blank name is refused" do
      refute Identity.present?()
      Social.subscribe()

      assert {:error, :name_required} = Social.save_profile("   ")
      refute Identity.present?()

      assert {:ok, %Profile{name: "Sample Name", created_at: first}} = Social.save_profile("  Sample Name ")
      assert Identity.present?()
      me = Identity.pubkey()
      assert_receive {:profile_updated, %ProfileUpdated{pubkey: ^me}}, 500
      assert %Profile{name: "Sample Name"} = Social.own_profile()

      # A second save within the same second is stamped strictly after the first.
      assert {:ok, %Profile{name: "Renamed", created_at: second}} = Social.save_profile("Renamed")
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
      bad = Event.sign(Event.new(%{pubkey: @friend_pubkey, created_at: 1, kind: 12_160, tags: [], content: "x"}), @friend_secret)
      assert {:error, :bad_content} = Social.ingest_profile(bad)
    end
  end

  describe "pruning" do
    test "removing a friend removes their profile; replacing the identity removes the old own row" do
      {:ok, _friend} = Social.add_friend(@friend_pubkey, "Nick")
      {:ok, _profile} = Social.ingest_profile(friend_profile("One", 1_700_000_000))
      :ok = Social.remove_friend(@friend_pubkey)
      assert Social.people() == %{}
      assert Repo.all(Profile) == []

      {:ok, _profile} = Social.save_profile("Me")
      old = Identity.pubkey()
      :ok = Social.import_identity(Keys.to_nsec(Secret.wrap(String.duplicate("0", 63) <> "5")))
      refute Identity.pubkey() == old
      assert Repo.all(Profile) == []
      assert Social.own_profile() == nil
    end
  end

  test "own_event_kind/1 names the own profile and nothing else" do
    {:ok, _profile} = Social.save_profile("Me")
    [event] = Social.own_events()
    assert Social.own_event_kind(event.id) == :profile
    assert Social.own_event_kind("nope") == nil
  end
end
```

Run both files: red.

- [ ] **Step 3: Migration**

`priv/repo/migrations/20260928100000_create_profiles.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.CreateProfiles do
  @moduledoc """
  One profile per known public key (ADR-073): what the key published
  about itself. `raw_event` keeps the signed wire form for republish;
  `created_at` is the wire time that decides which copy wins. A row
  exists only for the identity and roster members.
  """
  use Ecto.Migration

  def change do
    create table(:profiles, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :pubkey, :text, null: false
      add :name, :text
      add :raw_event, :map, null: false
      add :created_at, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:profiles, [:pubkey])
  end
end
```

- [ ] **Step 4: The schema**

`lib/media_centaur/social/profile.ex`:

```elixir
defmodule MediaCentaur.Social.Profile do
  @moduledoc """
  What a public key published about itself (ADR-073): its name, or
  nothing yet. One row per known key, replaced whole by a newer event;
  `raw_event` is the signed wire form the own-events diff republishes,
  `created_at` the wire time that decides which copy wins. The reader's
  own is a row like any other, under the identity's key. Built and read
  through `Social` (`save_profile/1`, `ingest_profile/1`, `own_profile/0`);
  the wire shape is `Profile.Translation`'s.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "profiles" do
    field :pubkey, :string
    field :name, :string
    field :raw_event, :map
    field :created_at, :integer

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Changeset from `Translation.from_event/1`'s attrs."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(profile \\ %__MODULE__{}, attrs) do
    profile
    |> cast(attrs, [:pubkey, :name, :raw_event, :created_at])
    |> validate_required([:pubkey, :raw_event, :created_at])
    |> validate_format(:pubkey, ~r/^[0-9a-f]{64}$/)
    |> unique_constraint(:pubkey)
  end
end
```

- [ ] **Step 5: The translation**

`lib/media_centaur/social/profile/translation.ex`:

```elixir
defmodule MediaCentaur.Social.Profile.Translation do
  @moduledoc """
  The profile's wire shape, both ways, pure (ADR-073;
  `docs/social-protocol.md` § Profile). Kind 12160, the first kind of
  the replaceable block: one record per signer, no tags. Content is
  `{"v": 1, "name": <string>}`; an absent or blank name means the key
  gives none. A name is capped at #{50} characters. Anything malformed
  is dropped whole: an unknown `v`, content that is not a JSON object,
  a name that is not a string or is over the cap. Unknown fields are
  ignored, so fields can be added without a version bump.
  """

  alias MediaCentaur.Nostr.Event

  @kind 12_160
  @content_version 1
  @max_name_length 50

  @type attrs :: %{
          pubkey: String.t(),
          name: String.t() | nil,
          raw_event: map(),
          created_at: non_neg_integer()
        }

  @doc "The profile's kind number."
  @spec kind() :: 12_160
  def kind, do: @kind

  @doc "The name cap in characters; the Settings form and the protocol page mirror it."
  @spec max_name_length() :: 50
  def max_name_length, do: @max_name_length

  @doc "An unsigned profile event for `pubkey` at `created_at`; a nil name is left off the wire."
  @spec to_event(String.t() | nil, String.t(), non_neg_integer()) :: Event.t()
  def to_event(name, pubkey, created_at) do
    content = if name, do: %{"v" => @content_version, "name" => name}, else: %{"v" => @content_version}

    Event.new(%{
      pubkey: pubkey,
      created_at: created_at,
      kind: @kind,
      tags: [],
      content: Jason.encode!(content)
    })
  end

  @doc "The attrs a verified profile event carries, or why it is dropped."
  @spec from_event(Event.t()) :: {:ok, attrs()} | {:error, :wrong_kind | :bad_content | :unsupported_version}
  def from_event(%Event{kind: @kind} = event) do
    with {:ok, content} <- decode(event.content),
         :ok <- check_version(content),
         {:ok, name} <- read_name(content) do
      {:ok, %{pubkey: event.pubkey, name: name, raw_event: Event.to_map(event), created_at: event.created_at}}
    end
  end

  def from_event(%Event{}), do: {:error, :wrong_kind}

  defp decode(content) do
    case Jason.decode(content) do
      {:ok, %{} = map} -> {:ok, map}
      _other -> {:error, :bad_content}
    end
  end

  defp check_version(%{"v" => version}) when version in [nil, @content_version], do: :ok
  defp check_version(%{"v" => _other}), do: {:error, :unsupported_version}
  defp check_version(_content), do: :ok

  defp read_name(%{"name" => name}) when is_binary(name) do
    case String.trim(name) do
      "" -> {:ok, nil}
      trimmed when byte_size(trimmed) > 0 and String.length(trimmed) <= @max_name_length -> {:ok, trimmed}
      _too_long -> {:error, :bad_content}
    end
  end

  defp read_name(%{"name" => nil}), do: {:ok, nil}
  defp read_name(%{"name" => _not_a_string}), do: {:error, :bad_content}
  defp read_name(_absent), do: {:ok, nil}
end
```

- [ ] **Step 6: The event**

In `lib/media_centaur/social/events.ex` add:

```elixir
  defmodule ProfileUpdated do
    @moduledoc "A known key's profile was stored: ingested from a relay, or the reader's own saved."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end
```

`| ProfileUpdated.t()` in the union and `def broadcast(%ProfileUpdated{} = event), do: publish({:profile_updated, event})`. In `lib/media_centaur/topics.ex:61` add `{:profile_updated, _}` to the `social:updates` row.

- [ ] **Step 7: The context**

In `lib/media_centaur/social.ex`: add `Events.ProfileUpdated`, `Profile`, `Profile.Translation` to the Boundary `exports` (alphabetical); alias `MediaCentaur.Nostr.Event`, `MediaCentaur.Social.Profile`, `MediaCentaur.Social.Profile.Translation, as: ProfileTranslation`. Add these functions (after the people functions):

```elixir
  # --- profiles ----------------------------------------------------------------

  @doc """
  Saves the reader's own profile (ADR-073, UIDR-047): mints the identity
  when none exists, stamps the event strictly after the stored one,
  signs, stores, publishes to every connected relay and broadcasts
  `ProfileUpdated`. The name is required: the form refuses to save
  without one.
  """
  @spec save_profile(String.t()) :: {:ok, Profile.t()} | {:error, :name_required}
  def save_profile(name) when is_binary(name) do
    with {:ok, name} <- present_name(name) do
      secret = Identity.ensure()
      me = Identity.pubkey()
      stored = Repo.get_by(Profile, pubkey: me)
      created_at = Event.stamp_after(stored && stored.created_at, System.os_time(:second))
      event = name |> ProfileTranslation.to_event(me, created_at) |> Event.sign(secret)
      {:ok, attrs} = ProfileTranslation.from_event(event)
      profile = upsert_profile(stored, attrs)
      Connections.publish(event)
      Events.broadcast(%Events.ProfileUpdated{pubkey: me})
      {:ok, profile}
    end
  end

  @doc """
  Stores a verified profile event from a known key (the identity or the
  roster): newer wins, a tie or an older one is `:ignored`, anything
  malformed is dropped whole. Broadcasts `ProfileUpdated` when stored.
  """
  @spec ingest_profile(Event.t()) ::
          {:ok, Profile.t()} | :ignored | {:error, :unknown_author | :wrong_kind | :bad_content | :unsupported_version | term()}
  def ingest_profile(%Event{} = event) do
    with :ok <- Event.verify(event),
         :ok <- known_key_or_error(event.pubkey),
         {:ok, attrs} <- ProfileTranslation.from_event(event) do
      case Repo.get_by(Profile, pubkey: attrs.pubkey) do
        %Profile{created_at: held} when held >= attrs.created_at ->
          :ignored

        stored ->
          profile = upsert_profile(stored, attrs)
          Events.broadcast(%Events.ProfileUpdated{pubkey: profile.pubkey})
          {:ok, profile}
      end
    end
  end

  @doc "The reader's own profile, or nil before one was saved."
  @spec own_profile() :: Profile.t() | nil
  def own_profile do
    case Identity.pubkey() do
      nil -> nil
      me -> Repo.get_by(Profile, pubkey: me)
    end
  end

  @doc "The own profile as a wire event, for the own-events diff; `[]` before one exists."
  @spec own_events() :: [Event.t()]
  def own_events do
    case own_profile() do
      nil ->
        []

      %Profile{raw_event: raw} ->
        case Event.from_map(raw) do
          {:ok, event} -> [event]
          {:error, _reason} -> []
        end
    end
  end

  @doc "What an own event with this id is, for the words a relay's refusal takes: `:profile`, or nil."
  @spec own_event_kind(String.t()) :: :profile | nil
  def own_event_kind(event_id) when is_binary(event_id) do
    case own_profile() do
      %Profile{raw_event: %{"id" => ^event_id}} -> :profile
      _other -> nil
    end
  end

  @doc """
  Replaces the identity with another secret key and forgets the old
  key's own profile row, which no longer names anyone the reader is.
  The new key's profile arrives from the relays if one was ever
  published.
  """
  @spec import_identity(String.t()) :: :ok | {:error, :invalid_secret}
  def import_identity(nsec) when is_binary(nsec) do
    old = Identity.pubkey()

    with :ok <- Identity.import_nsec(nsec) do
      if old, do: delete_profile(old)
      :ok
    end
  end

  defp upsert_profile(nil, attrs), do: Repo.insert!(Profile.changeset(attrs))
  defp upsert_profile(%Profile{} = stored, attrs), do: Repo.update!(Profile.changeset(stored, attrs))

  defp delete_profile(pubkey), do: Repo.delete_all(from(profile in Profile, where: profile.pubkey == ^pubkey))

  defp known_key_or_error(pubkey), do: if(known_key?(pubkey), do: :ok, else: {:error, :unknown_author})
```

In `remove_friend/1`, after `Repo.delete!(friend)` add `delete_profile(friend.pubkey)`.

`people/0` joins the profiles:

```elixir
  def people do
    names = Map.new(Repo.all(Profile), &{&1.pubkey, &1.name})
    friends = Map.new(list_friends(), &{&1.pubkey, person_for(&1, names)})

    case Identity.pubkey() do
      nil -> friends
      me -> Map.put(friends, me, own_person_for(me, Map.get(names, me)))
    end
  end

  def own_person, do: own_person_for(Identity.pubkey(), own_profile() && own_profile().name)

  defp own_person_for(pubkey, published_name),
    do: %Person{pubkey: pubkey, own?: true, published_name: published_name, short_npub: pubkey && short_npub(pubkey)}

  defp person_for(%Friend{} = friend, names) do
    %Person{
      pubkey: friend.pubkey,
      name_override: friend.name_override,
      published_name: Map.get(names, friend.pubkey),
      own?: false,
      short_npub: short_npub(friend.pubkey),
      added_on: DateTime.to_date(friend.inserted_at)
    }
  end
```

(`Person.published_name` is added in Task 4; write Tasks 3 and 4 in one sitting and run their tests together, or add the field first. The order below assumes the field exists: do Task 4 Step 3 before compiling Task 3.)

Update the `Social` moduledoc: add "and each key's published profile (`Social.Profile`), saved by the reader for their own key and ingested for a friend's". In `lib/media_centaur/social/identity.ex` fix the stale moduledoc line "Activities.review/2" to "Activities.review/3" and add "and `Social.save_profile/1`, the Settings path" to the minting sentence.

- [ ] **Step 8: Green, commit**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/`. Expected: PASS (profile, translation, friend, person, identity, relay, connections tests).

```bash
git add priv/repo/migrations/20260928100000_create_profiles.exs lib/media_centaur/social/profile.ex lib/media_centaur/social/profile/translation.ex lib/media_centaur/social.ex lib/media_centaur/social/events.ex lib/media_centaur/social/identity.ex lib/media_centaur/topics.ex test/media_centaur/social/profile_translation_test.exs test/media_centaur/social/profile_test.exs
git commit -m "feat: Social.Profile, what a key published about itself; save, ingest, own events, pruning; ProfileUpdated"
```

Run `~/scripts/agents/agent-mix ecto.migrate` so the dev daily driver's database has the table.

---

### Task 4: `Person.published_name`, `Person.name/1`, Unnamed

**Files:**
- Modify: `lib/media_centaur/social/person.ex`, `lib/media_centaur/format.ex`, `test/support/discovery_rows.ex`
- Test: `test/media_centaur/social/person_test.exs`

- [ ] **Step 1: Tests**

In `person_test.exs`: replace the test "Format.person_name/1 has no words yet for a friend without a name" with:

```elixir
  test "Person.name/1 is the override, else the published name, else nil" do
    assert Person.name(%Person{pubkey: @friend, name_override: "Nick", published_name: "Nicholas"}) == "Nick"
    assert Person.name(%Person{pubkey: @friend, published_name: "Nicholas"}) == "Nicholas"
    assert Person.name(%Person{pubkey: @friend}) == nil
  end

  test "Format.person_name/1 says You, the name, or Unnamed" do
    assert Format.person_name(%Person{pubkey: "me", own?: true}) == "You"
    assert Format.person_name(%Person{pubkey: @friend, name_override: "Nick", published_name: "Nicholas"}) == "Nick"
    assert Format.person_name(%Person{pubkey: @friend, published_name: "Nicholas"}) == "Nicholas"
    assert Format.person_name(%Person{pubkey: @friend}) == "Unnamed"
  end
```

and in the `people/0` test assert `published_name: nil` on the friend and, after `Social.save_profile("Me")`, that `Social.people()[me].published_name == "Me"`. Run: red.

- [ ] **Step 2: The struct and the words**

`lib/media_centaur/social/person.ex`: add `:published_name` to `defstruct` (after `:name_override`) and `published_name: String.t() | nil` to the type; add:

```elixir
  @doc "The name the reader sees: the override, else the published name, else nil."
  @spec name(t()) :: String.t() | nil
  def name(%__MODULE__{name_override: override, published_name: published}), do: override || published
```

Rewrite the moduledoc: "`name_override` is the reader's word for a friend; `published_name` is what the key said about itself (`Social.Profile`); `name/1` resolves them. The avatar URL is nil until phase 3 fills it. …" and drop the "nil until the profile event arrives" sentence.

`lib/media_centaur/format.ex`: replace `person_name/1` and its doc:

```elixir
  @doc """
  The words for a `MediaCentaur.Social.Person` (UIDR-047): "You" for the
  reader's own, else the name the reader sees, else "Unnamed". The one
  place the two words exist.
  """
  @spec person_name(MediaCentaur.Social.Person.t()) :: String.t()
  def person_name(%MediaCentaur.Social.Person{own?: true}), do: "You"

  def person_name(%MediaCentaur.Social.Person{} = person),
    do: MediaCentaur.Social.Person.name(person) || "Unnamed"
```

`test/support/discovery_rows.ex`: `person/2` gains `published_name: Keyword.get(opts, :published_name)`, and its `name` argument may be nil: change the guard to `when is_binary(name) or is_nil(name)` and the doc to "nil is a friend without an override".

- [ ] **Step 3: Green, commit**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/ test/media_centaur_web/components/discovery/ test/media_centaur_web/live/discovery_live/`. Expected: PASS.

```bash
git add lib/media_centaur/social/person.ex lib/media_centaur/format.ex test/support/discovery_rows.ex test/media_centaur/social/person_test.exs
git commit -m "feat: a Person carries the published name; Person.name resolves; person_name says Unnamed"
```

---

### Task 5: The sync loop moves to `RelaySync` and carries profiles

**Files:**
- Create: `lib/media_centaur/relay_sync.ex` (from `lib/media_centaur/activities/sync.ex`), `test/media_centaur/relay_sync_test.exs` (from `test/media_centaur/activities/sync_test.exs`)
- Delete: `lib/media_centaur/activities/sync.ex`, `test/media_centaur/activities/sync_test.exs`
- Modify: `lib/media_centaur/application.ex:10` (Boundary dep), `:292-296`; `lib/media_centaur/log/component.ex:95-98`; `test/support/global_state_sandbox.ex:121`; `lib/media_centaur/activities.ex` moduledoc (`:32`), `lib/media_centaur/social/relay.ex:7` doc

- [ ] **Step 1: Move**

```bash
git mv lib/media_centaur/activities/sync.ex lib/media_centaur/relay_sync.ex
git mv test/media_centaur/activities/sync_test.exs test/media_centaur/relay_sync_test.exs
```

Rename the module `MediaCentaur.Activities.Sync` → `MediaCentaur.RelaySync` in both files (and the test module name → `MediaCentaur.RelaySyncTest`). Add to the module head, before `use GenServer`:

```elixir
  use Boundary, deps: [MediaCentaur.Activities, MediaCentaur.Nostr, MediaCentaur.Social], exports: []
```

Rewrite the moduledoc's opening: "The loop that keeps stored rows in step with the relays (ADR-074): activities and deletions for `Activities`, profiles for `Social`. Neither context may depend on the other, so the loop sits above both. …" and keep the rest of the message protocol as it is, adding kind 12160 wherever the kinds are listed.

- [ ] **Step 2: Tests for the two new behaviours**

In `test/media_centaur/relay_sync_test.exs`, alias `MediaCentaur.Social.Profile.Translation, as: ProfileTranslation` and add (the file's existing setup starts `Connections.Owner` and the sync by hand; the module name in `start_supervised!` becomes `RelaySync`):

```elixir
  test "the feed carries kind 12160 and a friend's profile lands as their published name" do
    profile = Event.sign(ProfileTranslation.to_event("Nicholas", @friend_pubkey, 1_700_000_000), @friend_secret)
    relay = FakeRelay.start(events: [profile])
    Social.add_relay(relay.url)

    assert_receive {:relay_in, ["REQ", "feed", %{"kinds" => kinds}]}, 2_000
    assert 12_160 in kinds

    assert_eventually(fn -> Social.people()[@friend_pubkey].published_name == "Nicholas" end)
  end

  test "the own-events diff publishes the reader's profile to a relay that lacks it, once" do
    {:ok, _profile} = Social.save_profile("Me")
    relay = FakeRelay.start()
    Social.add_relay(relay.url)

    assert_receive {:relay_in, ["EVENT", %{"kind" => 12_160, "content" => content}]}, 2_000
    assert Jason.decode!(content)["name"] == "Me"
    refute_receive {:relay_in, ["EVENT", %{"kind" => 12_160}]}, 300
  end

  test "a relay that refuses the profile is named for it" do
    {:ok, _profile} = Social.save_profile("Me")
    relay = FakeRelay.start(accept: false, reason: "blocked: kind 12160 is not stored by this relay")
    Social.add_relay(relay.url)

    assert_logged(~r/rejected a profile: blocked: kind 12160/)
  end
```

Use the file's existing helpers for waiting and log assertions (`assert_logged`, and whatever the paging test uses to wait; if there is no `assert_eventually`, use `render_until`'s sibling for processes or a short `Process.sleep` loop as the file already does). Update the existing kinds assertion (`[32161, 32163, 32164, 5]`) to include `12160`.

Run: `~/scripts/agents/agent-mix test test/media_centaur/relay_sync_test.exs`. Expected: red on the three new tests and the kinds assertion.

- [ ] **Step 3: The loop carries both contexts**

In `lib/media_centaur/relay_sync.ex`: alias `MediaCentaur.Social.Profile.Translation, as: ProfileTranslation`.

`kinds/0`:

```elixir
  defp kinds, do: Translation.kinds() ++ [Translation.deletion_kind(), ProfileTranslation.kind()]
```

The `{:event, sub_id, event}` clause dispatches:

```elixir
    case ingest(event) do
```

with

```elixir
  # Each context ingests its own kinds; the loop only routes.
  defp ingest(%{kind: kind} = event) do
    if kind == ProfileTranslation.kind(), do: Social.ingest_profile(event), else: Activities.ingest(event)
  end
```

`publish_missing/2`:

```elixir
    missing = Enum.reject(Activities.own_events() ++ Social.own_events(), &MapSet.member?(seen, &1.id))
```

The refusal clause:

```elixir
      "#{url} rejected #{refused(Activities.own_event_kind(event_id) || Social.own_event_kind(event_id))}: #{reason}"
```

and `defp refused(:profile), do: "a profile"` beside the others.

- [ ] **Step 4: Registration**

`lib/media_centaur/application.ex`: the Boundary dep `MediaCentaur.Activities` at line 10 gains `MediaCentaur.RelaySync` beside it (keep Activities if other code there needs it; the compiler will say). `activities_sync_children/0` becomes `relay_sync_children/0` returning `[MediaCentaur.RelaySync]` under the same `:start_activities_sync` gate (keep the config key; renaming it touches `config/test.exs` and docs for no gain, and note in the moduledoc that the key predates the move). `lib/media_centaur/log/component.ex`: add `"relay_sync" => :social,` beside `"activities" => :social` and extend the comment ("the roster, the activity sync and the relay loop are the social graph"). `test/support/global_state_sandbox.ex:121`: the key becomes `MediaCentaur.RelaySync`. `activities.ex:32` and `social/relay.ex:7`: point at `RelaySync`.

- [ ] **Step 5: Green, commit**

Run: `~/scripts/agents/agent-mix compile --force --warnings-as-errors` (a new Boundary needs a forced compile), then `~/scripts/agents/agent-mix test test/media_centaur/relay_sync_test.exs test/media_centaur/social/ test/media_centaur/activities/`. Expected: PASS.

```bash
git add -A lib/media_centaur test/media_centaur/relay_sync_test.exs test/support/global_state_sandbox.ex
git commit -m "refactor: the sync loop is RelaySync, above Activities and Social; it carries profiles"
```

---

### Task 6: Settings opens on Your profile; saving it mints the identity

**Files:**
- Modify: `lib/media_centaur_web/live/settings_live/social_section.ex`, `lib/media_centaur_web/live/settings_live.ex:324-332` (`load_social/2`), `:886-915` (handlers), `:1516-1524` (`identity_changed`), `:1953-1966` (render)
- Test: `test/media_centaur_web/live/settings_live_test.exs` (find the `describe` for the social section; read it whole)

- [ ] **Step 1: Tests**

In the social describe of `settings_live_test.exs`, add (adapting selectors to the file's idiom):

```elixir
    test "opening Social mints nothing; Create profile mints the identity and shows the identity card", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/settings?section=social")
      refute Identity.present?()
      assert has_element?(view, "#profile-form")
      refute has_element?(view, "#identity-npub")
      refute has_element?(view, "#add-relay-form")

      view |> form("#profile-form", %{"name" => "   "}) |> render_submit()
      assert render(view) =~ "Give yourself a name"
      refute Identity.present?()

      view |> form("#profile-form", %{"name" => "Sample Name"}) |> render_submit()
      assert Identity.present?()
      assert has_element?(view, "#identity-npub", Identity.npub())
      assert has_element?(view, "#add-relay-form")
      assert has_element?(view, "#profile-form input[name='name'][value='Sample Name']")
      assert %{name: "Sample Name"} = Social.own_profile()
    end

    test "an identity without a profile shows both cards, the name empty", %{conn: conn} do
      Identity.ensure()
      {:ok, view, _html} = live(conn, "/settings?section=social")
      assert has_element?(view, "#identity-npub")
      assert has_element?(view, "#profile-form input[name='name']:not([value])")
    end
```

Existing tests that relied on opening the section to mint (they assert `#identity-npub` right after `live/2`) now need `Identity.ensure()` in their setup; update each and say which in the report. Run the file: red.

- [ ] **Step 2: The section**

In `social_section.ex`: `attr :npub, :string, default: nil, doc: "nil before an identity exists"`; add `attr :profile_name, :string, required: true, doc: "the saved name, or \"\""`; add `attr :name_cap, :integer, required: true`. Insert a first card before "Your identity" and gate the other three cards:

```heex
      <.settings_card
        title="Your profile"
        description="The name your friends see you under. Saving it creates your identity the first time."
      >
        <form id="profile-form" phx-submit="save_profile" class="flex items-center gap-2">
          <.settings_input
            name="name"
            value={@profile_name}
            placeholder="Name"
            maxlength={@name_cap}
            autocomplete="off"
            class="min-w-0 flex-1"
          />
          <.button type="submit" variant="neutral" size="sm" data-nav-item tabindex="0">
            {if @npub, do: "Save", else: "Create profile"}
          </.button>
        </form>
      </.settings_card>

      <.settings_card :if={@npub} title="Your identity" …>   <%!-- the existing card, unchanged inside --%>
```

and `:if={@npub}` on the Relays and Sharing cards too. Check `settings_input`'s attrs (`lib/media_centaur_web/components/settings.ex:288-318`) for `maxlength`/`rest` and `class`; pass through `rest` if needed.

- [ ] **Step 3: The LiveView**

`load_social/2`:

```elixir
  # Opening the Social section mints nothing: Create profile does
  # (`Social.save_profile/1`), and publishing an own activity still mints
  # silently (`Activities`). Without an identity only the profile card shows.
  defp load_social(socket, "social") do
    socket
    |> assign(identity_npub: Identity.npub(), nsec_revealed: nil, import_armed?: false, import_draft: "")
    |> assign(profile_name: profile_name(), name_cap: Social.Profile.Translation.max_name_length())
    |> assign(relay_status: Connections.status())
    |> assign(share_watched?: ShareWatched.enabled?(), share_watchlist?: ShareWatchlist.enabled?())
    |> load_relays()
  end

  defp profile_name, do: (Social.own_profile() && Social.own_profile().name) || ""
```

Handler, beside the identity handlers:

```elixir
  def handle_event("save_profile", %{"name" => name}, socket) do
    case Social.save_profile(name) do
      {:ok, _profile} -> {:noreply, socket |> load_social("social") |> put_flash(:info, "Profile saved")}
      {:error, :name_required} -> {:noreply, put_flash(socket, :error, "Give yourself a name")}
    end
  end
```

`import_nsec`'s second clause calls `Social.import_identity(nsec)` instead of `Identity.import_nsec(nsec)`. The `{:identity_changed, _}` clause also reassigns `profile_name: profile_name()`. Add `def handle_info({:profile_updated, _event}, socket), do: {:noreply, assign(socket, profile_name: profile_name())}` (the view already subscribes to `social:updates`). The render passes `profile_name={@profile_name} name_cap={@name_cap}`.

Run the writing-copy skill over: the card title and description, "Name", "Save", "Create profile", "Profile saved", "Give yourself a name".

- [ ] **Step 4: Green, browser, commit**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/settings_live_test.exs`. Expected: PASS. Then `~/scripts/agents/page-shot --url http://localhost:2160/settings?section=social --viewport 1920x1080 --wait-ms 3000` and Read it: the profile card first with the owner's current state (an identity exists on the daily driver, so the identity card follows).

```bash
git add lib/media_centaur_web/live/settings_live/social_section.ex lib/media_centaur_web/live/settings_live.ex test/media_centaur_web/live/settings_live_test.exs
git commit -m "feat: Settings opens on Your profile; saving it mints the identity; the identity, relays and sharing follow"
```

---

### Task 7: The `friends` rebuild and the optional name, Unnamed and the glyph on every surface

**Files:**
- Create: `priv/repo/migrations/20260928110000_friends_name_override_is_optional.exs`
- Modify: `lib/media_centaur/social/friend.ex`, `lib/media_centaur/social.ex` (`add_friend/2`, `set_name_override/2`, `present_name/1`), `lib/media_centaur_web/live/discovery_live.ex` (two handlers), `lib/media_centaur_web/live/discovery_live/add_friend_block.ex`, `lib/media_centaur_web/components/discovery/identity_tile.ex`, `lib/media_centaur_web/components/discovery/person_card.ex`, stories `identity_tile`, `person_card`, `feed_row`
- Test: `friend_test.exs`, `identity_tile_test.exs`, `person_card_test.exs`, `feed_row_test.exs`, `discovery_live_test.exs`

- [ ] **Step 1: Tests**

`friend_test.exs`: "the name is optional: none, or blank, is a friend without an override" (`add_friend(@pubkey)` and `add_friend(@pubkey, "  ")` both give `name_override: nil`); `set_name_override(@pubkey, "")` clears to nil and broadcasts; `set_name_override(@pubkey, nil)` on nil is silent; remove the `:name_required` assertions.

`identity_tile_test.exs`: add

```elixir
  test "a friend with no name at all is the person glyph, never a letter" do
    html = render(person: person(nil), size: 40)
    assert mark(html) == ["glyph"]
    assert letter(html) == ""
    assert html |> LazyHTML.query("[data-component='identity-tile'] .hero-user-solid") |> Enum.count() == 1
  end

  test "the published name gives the letter when there is no override" do
    assert letter(render(person: person(nil, published_name: "ada"), size: 40)) == "A"
  end
```

`person_card_test.exs`: the foot test asserts the placeholder is the published name, and `"Unnamed"` for a person with neither name; the h2 says "Unnamed". `feed_row_test.exs`: a friend with no name reads "Unnamed wants to watch" and the tile is `data-mark='glyph'`. `discovery_live_test.exs`: adding without a name shows "Unnamed"; clearing the override from the foot shows the published name (ingest a profile first with `Social.ingest_profile/1`) or Unnamed. Run: red.

- [ ] **Step 2: The rebuild**

`priv/repo/migrations/20260928110000_friends_name_override_is_optional.exs`:

```elixir
defmodule MediaCentaur.Repo.Migrations.FriendsNameOverrideIsOptional do
  @moduledoc """
  The reader's name for a friend becomes optional now that a published
  name exists to fall back on (UIDR-047). SQLite cannot relax NOT NULL in
  place, so the table is rebuilt: `name_override` becomes a real column,
  filled from `nickname`, and `nickname` stays as a nullable column the
  outgoing release still reads between `migrate` and its restart (the
  paired-release rule). The release after this one drops `nickname`.
  """
  use Ecto.Migration

  def up do
    create table(:friends_next, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :pubkey, :text, null: false
      add :nickname, :text
      add :name_override, :text

      timestamps(type: :utc_datetime)
    end

    execute """
    INSERT INTO friends_next (id, pubkey, nickname, name_override, inserted_at, updated_at)
    SELECT id, pubkey, nickname, nickname, inserted_at, updated_at FROM friends
    """

    drop table(:friends)
    rename table(:friends_next), to: table(:friends)
    create unique_index(:friends, [:pubkey])
  end

  def down do
    create table(:friends_prev, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :pubkey, :text, null: false
      add :nickname, :text, null: false

      timestamps(type: :utc_datetime)
    end

    execute """
    INSERT INTO friends_prev (id, pubkey, nickname, inserted_at, updated_at)
    SELECT id, pubkey, COALESCE(name_override, nickname, ''), inserted_at, updated_at FROM friends
    """

    drop table(:friends)
    rename table(:friends_prev), to: table(:friends)
    create unique_index(:friends, [:pubkey])
  end
end
```

If Credo's MC0015 reports the `execute`, put `# credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration` above each, as `20260902220000_drop_watchlist_flat_columns.exs` does.

- [ ] **Step 3: Schema and API**

`friend.ex`: `field :name_override, :string` (no `source:`); the changeset casts and `update_change(:name_override, &blank_to_nil/1)`, `validate_required([:pubkey])`; add the `blank_to_nil/1` from phase 1's first plan (nil → nil; a string → trimmed or nil). Moduledoc: drop the `source:` paragraph; say the override is optional and masks the published name.

`social.ex`: `add_friend(key, name \\ nil) when is_binary(key) and (is_binary(name) or is_nil(name))` with no `present_name` step (the changeset blanks); `set_name_override(pubkey, name) when is_binary(pubkey) and (is_binary(name) or is_nil(name))` → `with {:ok, friend} <- known_friend(pubkey), do: apply_change(friend, %{name_override: name})`; its spec loses `:name_required`. `present_name/1` stays for `save_profile/1`. Docs on both functions: the name is the reader's optional override.

- [ ] **Step 4: The surfaces**

`discovery_live.ex`: `add_friend` drops the `:name_required` clause; `set_friend_name` drops it too (a blank clears). `add_friend_block.ex`: the hint reads "Paste the key they give you. The name is yours for them and optional; without one you see the name they publish, or Unnamed." and the input's placeholder "Name, if you like". `identity_tile.ex`: import `icon: 1` from CoreComponents; `mark/1` becomes

```elixir
  defp mark(%Person{avatar_url: url}) when is_binary(url), do: :avatar
  defp mark(%Person{own?: false} = person), do: if(Person.name(person), do: :letter, else: :glyph)
  defp mark(%Person{own?: true}), do: :letter
```

with `<.icon :if={@mark == :glyph} name="hero-user-solid" class={@glyph_classes} />` in the template (glyph classes `size-5` at 40, `size-6` at 48) and the class branches keyed on `@mark != :avatar` for the fills. Moduledoc: the three marks; delete the "lands with phase 2" sentence. `person_card.ex`: the name input gains `placeholder={Format.person_name(%Person{@person | name_override: nil})}`. Stories: `identity_tile` adds a `glyph` variation per size; `person_card` adds `rail_unnamed`; `feed_row` adds `unnamed_listing`. Run the writing-copy skill over the hint and placeholder.

- [ ] **Step 5: Green, commit, migrate**

Run: `~/scripts/agents/agent-mix test test/media_centaur/social/friend_test.exs test/media_centaur_web/components/discovery/ test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/storybook_render_test.exs`. Expected: PASS. Then `~/scripts/agents/agent-mix ecto.migrate` for the dev database.

```bash
git add -A priv/repo/migrations lib/media_centaur/social lib/media_centaur_web storybook test
git commit -m "feat: a friend's name is optional; the published name, then Unnamed and the person glyph, stand in"
```

---

### Task 8: The whole suite and `precommit`

Run: `~/scripts/agents/agent-mix test` then `~/scripts/agents/agent-mix precommit` (foreground, timeout 600000). Fix what they report in the owning module; commit as `chore: precommit clean after the profile on the wire`.

---

### Task 9: Docs, protocol page, wiki, campaign

- `docs/social-protocol.md`: kind table row `| 12160 | Profile | Replaceable | Media Centaur |`; a `## Profile (kind 12160)` section after the activities (tags: none; content `v`, `name` string ≤ 50 optional; rules: newer wins, tie keeps stored, malformed dropped whole, never withdrawn, an absent name is rendered by the reader as Unnamed and no literal exists on the wire); the sync table's kinds gain 12160 and the own-events prose says "every own activity, deletion and profile"; § What a relay must do: kinds stored gains 12160 and a "Replaceable storage" row; the refusal table stands; a changes row for 2026-09-28. Then `scripts/sync-wiki-docs` regenerates the wiki's Social Protocol page.
- `docs/social.md`: the Contexts table gains `MediaCentaur.RelaySync` and `Profile` under Social; § Sync becomes RelaySync's; § Event shape gains the profile; § Web layer's Person paragraph says the published name is live; § PubSub lists `{:profile_updated, _}`.
- `docs/GLOSSARY.md`: Profile, Published name, RelaySync, Unnamed.
- Wiki: `Social.md` (Setup step: name yourself under Settings → Social first; Friends: the name is optional, Unnamed; What friends see), `Settings-Reference.md` (Your profile), `Hosting-a-Private-Relay.md` (v0.7.0 stores profiles), `Troubleshooting.md` (`blocked: kind 12160` means the relay predates v0.7.0).
- `campaigns/profiles.md`: status "Phase 2 shipped on main <date>; relay v0.7.0 committed in `../social-relay`, tag and push await the owner's ship"; decisions (the slot rule, `known_key?`, `stamp_after`); next steps (phase 3; the release after this drops `nickname`); the phase-1 follow-ups fulfilled here struck.
- Commit the app docs and the wiki (push neither).
