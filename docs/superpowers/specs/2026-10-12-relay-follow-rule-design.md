# Relay follow rule — design

Status: proposed, 2026-10-12. Supersedes one line of
[`2026-09-02-friends-recommendations-design.md`](2026-09-02-friends-recommendations-design.md):
"The app treats both [a private relay and a public relay] identically." It
no longer does.

## Glossary

- **Relay** — a Nostr server the reader configured (`Social.Relay`). Unchanged.
- **Follow rule** — the reader's choice, per relay, of who on it they follow.
  Two values. **Members**: everyone who publishes on the relay. **Added**: only
  people the reader added by key. Shown as *Everyone on this relay* and *Only
  people I add*. Default: added. Stored on the relay row.
- **Contact** — one row per public key the reader has a view of
  (`Social.Contact`, table `contacts`; today's `friends` table, widened). Holds
  the reader's state about the key: `added_at`, `name_override`,
  `show_avatar`, `hue_override`, `hidden`. Nothing here comes from the network.
- **Friend** — a contact the reader added (`added_at` set). Same meaning as
  today.
- **Member** — a key seen publishing on a relay whose follow rule is members.
  Observed, never configured. Recorded in `relay_members` (relay, pubkey,
  `seen_at`); rebuilt on every connect to that relay.
- **Followed key** — the identity, a friend, or a member of a members-rule
  relay. `Social.followed_key?/1`, the one gate both ingest paths use. Replaces
  `known_key?/1`.
- **Hidden** — a contact flag. A hidden person's activity makes no feed row,
  no glyph, no rail card; their profile is still ingested; their card sits in
  a collapsed group at the end of the Friends grid with a *Show* action.
- **Person** — the read model (`Social.Person`, ADR-074). Gains `hidden` and
  `friend?`. Unchanged otherwise.

## What the reader gets

Social runs on a relay: a small server one of your friends runs, or a
community runs. Three situations, two follow rules:

| Situation | Follow rule | What happens |
|---|---|---|
| A private group. A friend runs the relay and lets the group in. | Members | Join and you see everyone in the group; they see you. No list to build. Hide anyone you would rather not see. |
| A community you pick from. A club's or a forum's relay. | Added | Join and see nobody until you add a person by their key. |
| An open relay with a sign-up page. The operator approves applications. | Added | Same as above. A browsable member list is a later relay-side feature. |

The rule is chosen when the relay is added and can be changed on its row
under **Settings → Social → Relays**.

## Design

### Social context

**`Social.Relay`** gains `follow` (`Ecto.Enum`, `[:members, :added]`, default
`:added`). `Social.set_follow/2` changes it: on members → added it deletes the
relay's `relay_members` rows; either way it broadcasts
`Events.RelayChanged{url}`. `add_relay/2` takes the rule.

**`Social.Contact`** is the `friends` schema renamed, with `added_at`
(`utc_datetime`, nil for a member-only contact) and `hidden` (boolean, default
false). `add_friend/2` upserts a contact with `added_at` set (an existing
member-only row is promoted, overrides kept). `remove_friend/1` clears
`added_at`; the row, its profile and avatar are deleted only when the key is
not a member of any relay either. `set_hidden/2` flips the flag and broadcasts `Events.ContactChanged`
(`FriendChanged` renamed: it already fires for overrides, which now belong
to any contact; `FriendAdded` and `FriendRemoved` keep their names).

**`relay_members`**: `relay_id` (FK, `on_delete: :delete_all`), `pubkey`,
`seen_at`; unique on the pair. Two functions, both called only by `RelaySync`:

- `Social.note_member(url, pubkey)` — upsert, setting `seen_at` to now.
  Returns `:ok`; `:ignored` when the relay's rule is added. Creates the
  contact row when none exists.
- `Social.sweep_members(url, before)` — deletes the relay's rows with
  `seen_at < before`. Broadcasts `Events.MembersChanged{url}` when any row
  was deleted or any was created since `before`.

**`Social.followed_key?/1`**: identity, or contact with `added_at`, or a
`relay_members` row whose relay's rule is members. One query.

**`Social.people/0`**: every followed key as a `Person`, hidden included,
`friend?` set from `added_at`, `added_on` nil for a member-only contact.
Hidden people are excluded by the two `Activities` readers
(`list_activities/0`, `activities_for_refs/1`), not here: the Friends tab needs
them.

### Sync loop

`RelaySync` already knows which relay delivered each event. For a relay whose
rule is members:

1. `:connected` → subscribe `"feed"` with no `authors` (the relay restricts
   reads to members itself); record the connect time per URL.
2. `{:event, "feed", event}` → `Social.note_member(url, event.pubkey)`, then
   route as today.
3. When paging completes (the point that re-issues `"feed"` live today) →
   `Social.sweep_members(url, connected_at)`.

For an added-rule relay nothing changes. `Events.RelayChanged` joins the
roster events that re-issue `"feed"` on every connected relay.

A members-rule relay that is in fact public would pull in every author on it.
The guard is the control's copy, not machinery; a public relay is never a
friend group's.

### Web layer

- **Settings → Social → Relays**: the add form takes the URL and a select
  (*Everyone on this relay* / *Only people I add*, default the latter). Each
  relay row shows the same select; changing it calls `set_follow/2`. Composed
  from `Components.Settings`; the select is a kit component with a story.
- **Social → Friends**: a member-only card's foot reads *On relay.example*
  (the relay host) in place of *Added 3 Oct*, and carries *Hide* in place of
  *Remove friend*. A friend's card carries both. Hidden people form a
  collapsed group after the grid, name and *Show* only.
- **Feed, rail, glyphs, title view**: nothing new; hidden people fall out at
  the `Activities` seam.
- `FeedEntries.empty_reason/3` counts followed people, not friends. The
  empty-state copy names both ways to get people: add a relay as *Everyone
  on this relay*, or add a friend.

### Relay repository (required, same unit of work)

`unallowpubkey` removes the key from the member list and nothing else; the
key's stored events are still served to members on the next `REQ`
(`internal/relay/membership.go`, `onRequest` gates on the requester only).
Under the members rule the app would re-note that key on every connect. Fix:
the relay stops serving events whose author is not a member (filter query
results by author membership; re-allowing restores them). Contract page and
`docs/operating.md` updated. Until that ships, *Hide* is the reader's remedy
and the app needs no change when it does.

## Diff against the code

| Gap | Kind | Disposition |
|---|---|---|
| `known_key?/1` is the one ingest gate | existing seam | reuse, renamed |
| `people/0` is the one place a row becomes a person | existing seam | reuse |
| roster change resubscribes every relay | existing seam | extend to the relay rule |
| overrides live on `friends` alone; a member has no row | one idea, two homes | fix now: `contacts` |
| `remove_friend/1` deletes profile and avatar | wrong for a member | fix now: delete only when unfollowed |
| former member's events still served by the relay | relay-side | fix now in the relay repo |
| operator intent (NIP-11 hint preselecting the rule) | not needed yet | follow-up, out of scope |
| member directory for a public relay | not needed yet | follow-up, out of scope |

## Migration

One migration, no compatibility path: rename `friends` → `contacts`; add
`added_at` backfilled from `inserted_at`; add `hidden` default false; add
`relays.follow` default `"added"`; create `relay_members`. Every existing
relay keeps today's behaviour until the reader changes its rule. Nothing on
the wire changes, so an older app on the same relay keeps working.

## Testing

- `Social`: contact promotion and demotion; `followed_key?/1` across the
  three sources; `note_member` under each rule; `sweep_members` deletes only
  unseen rows and broadcasts once; `set_follow/2` members → added clears rows.
- `RelaySync` with `FakeRelay`: members rule subscribes without authors;
  note precedes ingest so an unknown member's event is stored; sweep after
  paging drops a key the relay no longer serves; rule change resubscribes.
- `Activities`: hidden author's rows absent from both readers; present again
  after *Show*.
- `SettingsLive`: add form rule select; row select changes the rule.
- `SocialLive`: member-only card foot and *Hide*; hidden group and *Show*;
  empty state copy with a members-rule relay and no activity yet.
- Stories for the select and the member card foot states.

## Documentation

Wiki `Social.md` (concepts, setup steps, Friends), `Settings-Reference.md`
(relay row), `Hosting-a-Private-Relay.md` (tell members to choose *Everyone on
this relay*). `docs/social.md` contexts and sync sections. Relay repo
`docs/protocol.md` and `docs/operating.md` for the served-events change.
