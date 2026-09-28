# Social (contributor guide)

**Social** is the subsystem that connects one install to friends' installs over
Nostr relays: this install's identity, its relays, its friends, and the
activities that travel between them — a title reviewed, watched, or
listed — and the profile each person publishes about themselves. A
**friend** is one roster entry inside it. How it is put together: four
contexts, one protocol library, one long-lived WebSocket per relay, and a
sync loop that keeps stored activities and profiles in step with what the
relays hold.

End-user setup lives on the wiki:
[Social](https://github.com/media-centaur/media-centaur/wiki/Social).
Design rationale and the build order live in
[`docs/superpowers/specs/2026-09-02-friends-recommendations-design.md`](superpowers/specs/2026-09-02-friends-recommendations-design.md),
[`docs/superpowers/specs/2026-09-05-social-activity-feed-design.md`](superpowers/specs/2026-09-05-social-activity-feed-design.md)
and `campaigns/friends-recommendations.md` (completed and removed — see git history).

- [Contexts](#contexts)
- [Identity and secrets](#identity-and-secrets)
- [Transport](#transport)
- [Event shape](#event-shape)
- [Sync](#sync)
- [PubSub topics](#pubsub-topics)
- [Web layer](#web-layer)
- [Health](#health)
- [Testing](#testing)
- [Development](#development)
- [Dependencies](#dependencies)
- [Scheduled migrations](#scheduled-migrations)

## Contexts

Five `Boundary` contexts, each with one job; `RelaySync` is the one above two of
them. The dependency edges run one way: `Discovery ← Activities → Social →
Nostr`, and `RelaySync → Activities, Social, Nostr`; `Activities` also reads
`Library`, `WatchHistory`, `Discovery` and `Settings.Preferences` to turn a
person's acts into activities. Neither `Activities` nor `Social` may depend on
the other's rows, so the loop that reconciles both with the relays sits above
them (ADR-074).

| Context | Owns | Depends on |
|---|---|---|
| `MediaCentaur.Nostr` | The protocol and nothing else: `Keys`, `Event`, `Filter`, `Connection`. No tables, no domain meaning. | — |
| `MediaCentaur.Social` | The network's *configuration* and who is on it: `Identity` (the keypair), `Relay` (`relays` table), `Friend` (`friends` table), `Connections` (one live connection per relay), `Profile` (`profiles` table, what each known key published about itself; `Profile.Translation`, events ↔ rows), and `Person`, a key as the reader sees it, built by `Social.people/0` (ADR-074). | `Nostr` |
| `MediaCentaur.Activities` | The *content*: `activities` table, `Translation` (events ↔ rows), `Publisher` (a person's acts → activities, behind the sharing toggles). | `Social`, `Nostr`, `TMDB`, `TmdbArtwork`, `Library`, `WatchHistory`, `Discovery`, `Settings.Preferences` |
| `MediaCentaur.RelaySync` | No tables. The loop that keeps both contexts' rows in step with the relays: subscribes, routes each event to its owning context, publishes what a relay lacks. | `Activities`, `Social`, `Nostr` |
| `MediaCentaur.Discovery` | The watchlist (`watchlist_items`). Knows nothing about the friend network — a row from the feed stores a bare `activity_id`. | `Library`, `TmdbArtwork`, `TMDB` |

The Discovery/Activities separation is deliberate: a watchlist row records
*intent*, an activity records *what a signed event said*. Joining them (who
reviewed a watchlist row, whether a feed row is already saved) is the web
layer's job — see [Web layer](#web-layer).

## Identity and secrets

`Social.Identity` holds one secp256k1 keypair. The secret is a single
**sensitive Settings config key**, `nostr_secret_key` (hex, wrapped in
`MediaCentaur.Secret` at rest and in memory); the public key is derived on every
read rather than stored, so the two can never disagree.

- `ensure/0` generates on first use. Two callers: `Social.save_profile/2`,
  when the reader saves their profile under Settings → Social (opening the
  section mints nothing, UIDR-047), and `Activities` publishing an own
  activity — a user can review a title before ever saving a profile, which
  mints the identity right there.
- `import_nsec/1` is the only replacement path, reached through
  `Social.import_identity/1` (two-click arm in the UI, MC0027 treatment b),
  which also deletes the old key's own profile row; re-importing the same
  key keeps it.
- Both broadcast `Social.Events.IdentityChanged`, which makes
  `Connections.Owner` rebuild every connection so `AUTH` answers are re-signed.

`Nostr.Keys` owns the hex ↔ bech32 (`npub` / `nsec`, NIP-19) conversions and
enforces `1 <= d < n` — `bitcoinex` would otherwise accept a zero scalar as a
private key. The secret is unwrapped in exactly three places: `Keys.private_key!/1`
(used by both `Keys.pubkey/1` and the signing call in `Nostr.Event`),
`Keys.to_nsec/1`, and `Identity.store!/1`.

## Transport

`Nostr.Connection` is one GenServer per relay URL: one WebSocket
(`mint_web_socket`), NIP-01 frames, and the NIP-42 `AUTH` handshake. It knows
nothing about what an event means. Its own statuses are `:connecting`,
`:connected`, `:disconnected`, `:auth_failed`; the owner's entry adds `:synced`
(below).

The owner (the pid passed as `owner`) receives `{:nostr, url, message}` — see the
`Nostr.Connection` moduledoc for the full message list. Behaviour worth knowing
before touching it:

- **Subscriptions live in the connection's state** and are re-issued after every
  reconnect *and* after a successful `AUTH` — an allowlist relay refuses `REQ`
  before authenticating.
- **Backoff** doubles from 1 s to 60 s and resets on connect. Mint's own connect
  timeout is capped at 5 s so an unreachable relay doesn't hold the process for
  30. Every `{:disconnected, reason, retry_in_ms}` carries the wait before the
  next attempt.
- **Liveness ping** every 30 s while connected; a pong missing after 10 s drops
  the socket as `:unresponsive` into the normal backoff. Without it a half-open
  socket stays "connected" until the kernel gives up. Each pong reaches the
  owner as `:pong`, so "last heard" stays fresh on a quiet relay.
- **One console line per outage** under `:nostr`: the loss of a live socket, or
  the first failed attempt after one. Retries are silent.
- **Reasons are words once** — `Nostr.Reason.describe/1` turns a transport term
  into "connection refused" / "host not found" / "timed out" / "TLS failed" /
  "closed by relay" / "unresponsive"; a relay's own `OK` / `CLOSED` / `AUTH`
  text passes through; anything unknown is "connection failed". No inspected
  struct reaches the UI.
- **`publish/2`, `subscribe/3`, `unsubscribe/2` are casts** — nothing blocks
  behind a connect attempt.
- **Every inbound frame is type-guarded.** A relay is untrusted input; a frame
  that doesn't match falls to a debug log, never a crash.

`Social.Connections` keeps that population in step with the `relays` table: a
Registry keyed by URL, a DynamicSupervisor, and `Connections.Owner`, which
reconciles on boot, on `RelayAdded` / `RelayRemoved` / `IdentityChanged`, and
on `{:config_updated, :nostr_secret_key, _}` — the boot reconcile runs before
`Application.post_supervisor_hooks/1` overlays the database settings, so the
identity is usually absent then and the overlay's broadcast is what starts
the connections —
receives every connection's messages, and re-broadcasts them on
`social:connections`. `Connections.status/0` is the read model —
`%{url => %{state, last_error, since, last_heard_at, retry_at}}` (the
`Connections.entry/0` typedoc defines each field). `state` names how far the
connection has got: `:connecting`, `:connected`, `:synced` (the relay answered
the feed subscription with `EOSE`, so it serves this identity's requests),
`:auth_failed`, `:disconnected`. A `CLOSED` on the feed whose reason starts
with `restricted:` is `:auth_failed` — khatru cannot refuse an `AUTH` event, so
that is the only signal a non-member gets. `since` is the onset of the current
state, which is what the health probe measures against; `connected?/1` is the
one predicate for "counts as connected" (`:connected` or `:synced`), used by
publish fan-out, sync, and every surface's connected-of-configured count.

The words for an entry live once, in `MediaCentaurWeb.RelayStatusRow`:
Connecting / Connected / Synced / Rejected / Not connected, plus the Status
drill-in's per-relay details (how long in the state, the newest complaint,
the next attempt, when last heard).

## Event shape

The wire contract — every kind, its tags and content fields, deletion, sync
and what a relay must do — is [`docs/social-protocol.md`](social-protocol.md)
(the wiki's *Social Protocol* page is generated from it). This section is the
implementation view.

`Activities.Translation` is the anti-corruption layer, and it is pure in
both directions. Three addressable kinds share one address and one content
envelope (`v`, `title`); each adds its own fields:

| Kind | Name | `d` tag | Content beyond the envelope |
|---|---|---|---|
| `32164` | Review | `tmdb:<media_type>:<tmdb_id>` | `sentiment` (`dislike` / `like` / `love`, absent = none), `text`, `reviewed_at` (32160, Recommendation, is retired — ADR-068) |
| `32161` | Watched | same | `watched_at`, `episode` (TV: `season_number`, `episode_number`, `name`) |
| `32163` | Listing | same | `listed_at` (32162, Tracking, is retired — never reused, dropped on read) |

A `p` tag is defined by the spec for directed reviews and never set.

Addressable means the relay keeps one event per `(author, kind, d)`, so
reviewing the same title twice — or finishing the next episode — replaces
rather than appends. The row mirrors that: identity is `(author_pubkey, kind,
tmdb_id, media_type)`, the wire time decides, and the embedded title and
episode use `on_replace: :delete` — the newer event's snapshot is the whole
truth, never a field-wise merge. The row's `acted_at` holds whichever domain
time the kind carries.

`from_event/1` shape-checks an already-*verified* event; the address and the
content snapshot must agree on identity, and a mismatch is rejected rather than
reconciled. `raw_event` keeps the signed wire form so the event can be
republished to a relay that lacks it. Sent vs received is derived by comparing
`author_pubkey` against the identity — no stored direction column can disagree
with the signature.

Review text is capped at 500 characters (`Activities`), matched by the
textarea's `maxlength`; a review's sentiment and text are both optional,
and a nil sentiment is left off the wire. Content carries `"v": 1`; `from_event/1` treats an
absent `v` as 1 and drops an unknown one.

**Producers.** Reviewing is an explicit act and always publishes
(`Activities.review/3`, from the Review modal, with the sentiment and text
the sender gave, neither required). Watched and listing
activities come from `Activities.Publisher`, a pubsub listener over
`watch_history:events` and `discovery:updates` that calls
`Activities.watched/2` / `listing/1` only while the `share_watched` /
`share_watchlist` preference is on (Settings → Social → Sharing, both default
off). A completion resolves its TMDB identity through `Library.ExternalIds`;
an entity without one, and every extra, is skipped. A listing follows the
rung transition: `Discovery.Events.RungChanged` carries `previous_rung`
and `rung`, and only the crossing onto List publishes — moving up the
ladder afterwards does not. Dropping below List (Off or Ignored) calls
`Activities.withdraw/3` on the listing whether or not the toggle is still
on: the statement is no longer true (ADR-067).

**Deletion.** `Activities.delete/1` withdraws an own row of any kind:
`Translation.to_deletion/5` builds the kind 5 (`a` =
`<kind>:<pubkey>:tmdb:<type>:<id>`, `e` = the event id), the row becomes a
tombstone (`deleted_at` + `deletion_event`, see the `Activity` moduledoc), the
deletion is published, and `Events.Deleted` goes out. `ingest/1` of a kind 5
(`Translation.from_deletion/1`, author must own the address) tombstones the
addressed row unless the row is newer; an activity older than a row's
tombstone is `:ignored`; a newer one revives. Every read excludes tombstones
except `own_events/0`, which yields the deletion of a withdrawn own row
instead of its activity.

**Two times.** `created_at` is the *wire* time: it decides which copy wins,
here (`upsert_if_newer`, `tombstone_applies?`, read off the stored events via
`Activity.event_created_at/1` / `deletion_created_at/1`) and on the
relay, and nothing else. The *domain* time is when the person acted —
`reviewed_at` / `watched_at` / `listed_at` in the content, a `deleted_at`
tag on the deletion — and is what `acted_at` / `deleted_at` on the row hold,
so ordering and display never move when a message is re-signed or arrives
late. A message without
its domain time gets the wire time as fallback.

**Stamping.** A relay keeps one record per address and, on a `created_at` tie,
keeps what it holds (a deletion beating an activity). So a new own activity is
stamped strictly after the activity or tombstone the row already holds, and
`delete/1` stamps the deletion no earlier than the activity it withdraws
(`Activities.stamp/3`, private, over `Nostr.Event.stamp_after/2`, which owns
the strictly-after rule). Without this
a same-second re-review would replace the row here, be discarded by
the relay, and be republished by the own-events diff on every connect.

**Profile.** `Social.Profile.Translation` is the profile's anti-corruption
layer, pure both ways: kind `12160`, replaceable, no tags, content
`{"v": 1, "name": <string>, "avatar": {"type": <type>, "data": <base64>}}`.
The caps live there alone (`max_name_length/0`, 50 characters;
`max_avatar_bytes/0`, 64 KB decoded, inclusive); the Settings form and the
protocol page mirror them. An absent or blank name reads as nil; an absent or
null avatar means none. An unknown `v`, content that is not a JSON object, a
name that is not a string or is over the cap, or an avatar whose type is not
`image/webp`, `image/png` or `image/jpeg`, whose data is not base64, whose
decoded bytes are over the cap or do not open with the type's signature drops
the event whole. The reader never decodes an avatar: `from_event/1` hands the
bytes on as `avatar_bytes` for the file store. `Social.Profile` is the row,
one per key (`pubkey` unique, `name`, `avatar_type`, `raw_event`,
`created_at`), for the identity and the roster only.

- `Social.save_profile/2` is the Settings form's save. It takes the name and
  an avatar change: `:keep` the stored avatar, `:none` to remove it, or
  `{:new, bytes}`, the WebP master `ImageFiles.square_webp/3` made; bytes over the cap are refused (`:avatar_too_large`). It refuses
  a blank name (`:name_required`) or one over the cap (`:name_too_long`) before
  minting anything (`Social.check_name/1` is the same rule, for the form),
  then mints the identity if none exists, stamps strictly after the stored
  profile (`Event.stamp_after/2`), signs, stores, publishes and broadcasts
  `ProfileUpdated`. `:keep` re-reads the stored file; when the file is
  missing the new profile carries no avatar.
- `Social.ingest_profile/1` verifies the signature, requires a known key
  (`Social.known_key?/1`: the identity or the roster), keeps the newer
  `created_at` (a tie or an older one is `:ignored`), stores the row and the
  avatar file, and broadcasts `ProfileUpdated` when it stores.
- `own_profile/0`, `own_events/0` (the stored own profile as a wire event, for
  the own-events diff) and `own_event_kind/1` (`:profile` for the refusal
  words) are what `RelaySync` reads.
- A profile is never withdrawn (ADR-073), so there is no deletion path.
  Removing a friend (`remove_friend/1`) deletes their row; replacing the
  identity (`import_identity/1`) deletes the old key's. Either removes the
  key's avatar file with it.

**Avatar storage.** The bytes never enter a column. `Social.AvatarStore`
keeps one file per key at `{data_dir}/images/social/<pubkey>.<ext>` (`webp`,
`png` or `jpg`, from the type); the row carries `avatar_type` alone and the
path is derived from the key and the type. `raw_event` carries the encoded
wire form, avatar included, for republish. `store_profile/2` writes the row,
then the file, or deletes the file when the profile has no avatar. Row first:
a write that fails after the row leaves a type with no file, which reads as
no avatar until a newer profile arrives; file first could serve new bytes
under the old URL. The URL is `ImageFiles.web_path/2` of the relative path
with the profile's `created_at` as `?v=`, so a replaced avatar gets a new URL
and `Plugs.ImageServer` serves an unchanged one as immutable; it never carries
`?w=`, since the tile paints the master as it is. `AvatarStore.url/3` returns
nil when the file is missing. `Social.people/0` selects four fields of each
profile (`pubkey`, `name`, `avatar_type`, `created_at`), leaving `raw_event`
unread on a page load.

## Sync

`MediaCentaur.RelaySync` is a GenServer over `social:connections` and
`social:updates`. It owns no rows: it subscribes, routes by kind to the
context that owns the event, and publishes what a relay lacks.

1. `:connected` for a relay → subscribe `"feed"` (authors = friends ++ self,
   kinds 32164, 32161, 32163, 5 and 12160, `limit` 500, no `since`) and
   `"own:<url>"` (authors = [self], same kinds) on that relay, and reset the
   seen-set for that URL.
2. `{:event, "feed", event}` → by kind: 12160 to `Social.ingest_profile/1`,
   every other kind to `Activities.ingest/1` (verify signature, require a
   known author, newest wins, deletions tombstone). Events on `"own:<url>"`
   also record their id in the seen-set.
3. `{:eose, "feed"}` → a full page asks for the next (`until` = oldest − 1);
   the first short page after paging re-issues `"feed"` live.
4. `{:eose, "own:<url>"}` → publish to that relay every stored own event it did
   *not* send — `Activities.own_events/0` (activities of live rows, deletions
   of withdrawn ones) followed by `Social.own_events/0` (the reader's
   profile). A per-relay diff, not a blanket re-publish.
5. A roster change on `social:updates` resubscribes `"feed"` on every connected
   relay with the new author list.
6. `{:ok, id, false, reason}` → a warning naming what the relay refused:
   the context that owns the event says what it is
   (`Activities.own_event_kind/1`, then `Social.own_event_kind/1`) and the
   loop words it ("rejected a deletion: …" / "rejected a review: …" /
   "rejected a watched activity: …" / "rejected a profile: …").
   `Connections` only keeps the reason as the relay row's last error. A relay
   refusing a deletion with `blocked: kind 5 is not stored by this relay` is a
   `social-relay` older than v0.3.0; one refusing kind 32161 is older than
   v0.4.0, one refusing 32163 older than v0.5.0, one refusing 32164 older than
   v0.6.0, one refusing 12160 older than v0.7.0 — and, because an old deletion
   parser only knows the coordinates of its day, that relay refuses the
   *deletion* of a watched activity or a listing with `blocked: only the
   author may delete an event`. Each is re-sent on every connect until the
   relay is upgraded.

There is no sync cursor: every connect reads the relay from the start. A relay
holds one record per signer per title, so the whole history is a page, and a
`since` keyed on `created_at` skipped an event published late with an older
stamp (a withdrawal made offline). Re-reading is idempotent.

Both ingest paths reject anything not signed by the identity or a key on the
roster (`Social.known_key?/1`), so a relay that hands over the whole world
still yields only what you follow.

On reconnect, `Connections.Owner` re-applies the relay's registered subscriptions
as well, so `"feed"` and `"own:<url>"` each go out twice. That is harmless
(relays de-duplicate identical subs, and the seen-set resets on `:connected`) and
is left alone rather than adding a seam to silence one sender.

## PubSub topics

All three are declared in `MediaCentaur.Topics`.

| Topic | Publisher | Messages |
|---|---|---|
| `social:updates` | `Social.Events` | `{:identity_changed, _}`, `{:relay_added, _}`, `{:relay_removed, _}`, `{:friend_added, _}`, `{:friend_changed, _}`, `{:friend_removed, _}`, `{:profile_updated, _}` |
| `social:connections` | `Social.Connections.Owner` | `{:relay_connection, url, message}` — the re-broadcast of every `Nostr.Connection` owner message |
| `activities:updates` | `Activities.Events` | `{:activity_received, _}`, `{:activity_sent, _}`, `{:activity_deleted, _}` — each payload carries the activity's `kind` |

Subscribers use `Social.subscribe/0`, `Social.subscribe_connections/0` and
`Activities.subscribe/0`. Payloads are typed structs per ADR-060.

`Connections.apply_message/2` is the owner's own fold over a connection message,
exported so a LiveView folding `social:connections` into local state can never
disagree with the owner about what a message meant.

## Web layer

`MediaCentaurWeb.DiscoveryLive` is one LiveView with a `live_action` per tab
(`:feed` at `/discovery`, `:watchlist`, `:friends`).

A person is drawn from one read model everywhere, `Social.Person`
(ADR-074): the reader's name for a friend (`name_override`, optional),
the name the key published (`published_name`, from its `Social.Profile`),
the avatar URL (`avatar_url`), the reader's per-friend switch
(`show_avatar`), and whether it is the reader's own. `Person.name/1` resolves the override, else the
published name, else nil. `Social.people/0` builds `%{pubkey => Person}`
for the identity and the roster, joining their profiles;
`Social.own_person/0` is the reader alone. `avatar_url` is nil when the key
published no avatar, the file is missing, or the reader switched the friend's
picture off: `Friend.show_avatar` is applied at the one seam, `Social`'s
private `person_for/2`, so no surface checks it.
`MediaCentaur.Format.person_name/1` gives the words: "You", the resolved
name, or "Unnamed". `Components.Discovery.IdentityTile` draws one of three
marks (UIDR-047): the avatar, the letter of those words,
or the person glyph for a friend with no name at all, so no letter is
invented from Unnamed. A `ProfileUpdated` reaches the page as
`{:profile_updated, _}` and reloads the people and the rows, so a
friend's published name is live.

Both social tabs
project one enriched list — every live activity with its actor
(`Activities.list_activities/0`) — two ways (UIDR-038):

- **Feed** — `DiscoveryLive.FeedEntries`: every author's reviews and
  listings, friends' and this identity's own, one
  `Components.Discovery.FeedEntry` per action, newest first, flat, a
  window of twenty to a cap of sixty (*Show older*) with a queued head
  ("N new" while scrolled; the `FeedHead` hook reports the column's
  head leaving the viewport), filtered by the `?scope=` param
  (Everyone, Friends, You — `parse_scope/1`; UIDR-045). Watched, former
  friends' and ignored-title rows make no row for any author.
  `ActivityArtwork` resolves each row's poster down
  `MediaCentaur.TitleArtwork`'s ladder (`Library.Artwork` is the
  library tier); the Feed carries no backdrop (UIDR-046).
  `Components.Discovery.FeedRow` renders one row — the identity tile,
  the poster, the words, the time at the edge — in a hairlined column,
  with its hover toolbar — `feed_list` (the bottom rung as a toggle;
  Following as plain state), `feed_download` (the modal's plain
  Download, same `Plans.plan_title/2` and flash) and, on a friend's row,
  `ignore_title` (with the Undo toast); an own row has no Ignore and no
  Delete — it opens the modal for its action, where Delete lives.
  Friend provenance for a listing or an ignore is
  `TitleIntent.friend_provenance/2`, the same spelling the modal uses.
- **Friends** — `DiscoveryLive.People` folds the list into one
  `People.Card` (a `Social.Person` and their acts) per known person,
  the reader first when an identity exists: the person's **acts**, one per title acted on,
  newest first, each carrying its flags (`Components.Title.Flag`, mast
  order) and which of them are at the grade (gold: two or more friends
  did that act on that title). `Components.Discovery.PersonCard`
  renders a person and their acts at two widths — the Feed's rail (`People.rail/1`: You
  first, then by latest act, eight at most) and the Friends grid — as
  the tile, the name and the acts strip of posters under their centred
  glyphs; no clock, no presence line, nothing about what a person
  withholds (UIDR-046). Every poster and opened-card row opens the title
  modal with `?title=<ref>&activity=<id>` so the modal speaks for that
  act; Delete on an own activity → `Activities.delete/1` lives there.
  The opened card's foot carries the reader's name for the friend
  (`Social.set_name_override/2`, the `set_friend_name` event; a blank
  clears it back to the published name) over the name it masks as the
  field's placeholder (`Format.person_name/1` of the person without the
  override: the published name, else Unnamed), the **Show their picture**
  switch (`Social.set_show_avatar/2`, the `set_show_avatar` event;
  `Friend.show_avatar`, on by default), the key, the added date and Remove
  friend. `DiscoveryLive.AddFriendBlock`, the add-friend form
  (still an iteration-phase component under `live/discovery_live/`),
  takes an npub and an optional name (`Social.add_friend/2`; placeholder
  "Name (optional)"); re-adding a key changes nothing. A rename
  broadcasts `Social.Events.FriendChanged`, and the page rebuilds its
  `people_by_pubkey` map from `Social.people/0`.

What friends did with a title — reviewed and with what sentiment, watched,
or listed — is one component everywhere but the Feed, the pennant
(`Components.Title.Pennant`, UIDR-037, six flags per UIDR-040; the
sentiment glyphs are `Components.Title.Sentiment`'s), fed by
`Activities.friend_activity_for/1` on the watchlist rows, the Incoming
search rows and both detail modals. A feed row flies none: each
action is its own row there. See
`docs/plans/2026-09-05-recommendation-pennant.md` for the original
decisions (written for the two-valued recommendation sentiment; UIDR-040
is the current rule).

The joins the contexts may not make happen here:

- **Activity rows** — `Activities.list_activities/0` returns the record plus
  its `author`, a `Social.Person`, for authors the reader knows; a former
  friend's rows are left out. `DiscoveryLive` adds `poster_url`, `library_owner_id`
  (`Library.ExternalIds.tmdb_owners/1`), `on_watchlist?`
  (`Discovery.watchlisted_refs/0`) and the acquisition state, then both
  projections read from that one list.
- **Watchlist rows** — the row stores only `activity_id`; the page resolves
  it through `Activities.get_row/1`, whose `author` may be nil for a
  removed friend.

Settings → Social (`SettingsLive.SocialSection`) is four cards. **Your
profile** comes first: the picture and the name, one form saved by
`Social.save_profile/2`; before an identity exists its button is **Create
profile**, and saving mints the identity. The picture is the app's one
LiveView upload (`allow_upload(:avatar)`): one JPEG, PNG or WebP up to 10 MB.
On save the form checks the name with `Social.check_name/1` before it
consumes the upload, so a name error leaves the chosen file pending; the
file then becomes the 256×256 WebP master (`ImageFiles.square_webp(path,
256, max_bytes)`: centre-cropped, flattened onto black, the source's
metadata stripped so a photo's GPS position never reaches the wire, the
quality stepped down until the bytes fit the cap), and a file libvips
cannot open is refused with a flash. **Remove**
marks the stored avatar for removal until the save (the tile shows the
letter meanwhile) and steps aside while a file is chosen; a chosen file wins
over a pending Remove. **Your identity**, **Relays** and **Sharing** appear
once an identity exists. Opening the section mints nothing.

`MediaCentaurWeb.Live.ReviewFlow` is the modal flow (`use ReviewFlow`
injects the handlers, the clearable sentiment choice included), hosted by
every `EntityModal` host for the library detail page and every
`TitleDetailHost` host for a title without files — the only places a
review is made. The sharing toggles live in
`SettingsLive.SocialSection`. The Review control is gated
on the `show_discovery` preference (`Settings.Preferences.DiscoveryVisibility`),
the same preference that gates the sidebar entry.

## Health

`Social.IncidentContext` is the `assess/0` the `ErrorReports.Evaluator` polls
(ADR-054), owning one `:subsystem` incident for the `friends` component. Its
faults are `:relay_auth_failed` (error, no grace), `:relays_unreachable` (error,
after a 180 s grace) and `:relay_degraded` (warning). No relays configured is
never a fault. The decision is the pure `decide/3`; `assess/0` is the shell.

Each fault carries a `headline:` — **Relay rejected this identity**, **No
relay reachable**, **A relay is unreachable** — which is the sentence the
health board shows. Faults bucket under the synthetic fingerprint
`subsystem:social:<kind>` (`Store.fault_fingerprint/2`), so the Social tile
colours the moment the evaluator raises one and clears the moment it resolves;
the drill-in below the tile shows the live per-relay rows
(`Components.StatusWidgets.Social`).

Console tags: `:nostr` for the wire (`Nostr.Connection`), `:social` for
everything above it (`Social`, `Activities`, `RelaySync`). `HealthBoard.normalize/1`
aliases `:nostr` incidents onto the Social tile.

## Testing

`MediaCentaur.Nostr.FakeRelay` (`test/support/nostr/fake_relay.ex`) is an
in-process relay: a `WebSock` handler under Bandit on an ephemeral loopback port,
speaking the subset `Nostr.Connection` uses (`EVENT` → `OK`, `REQ` → stored
matches then `EOSE`, `CLOSE`, optional `AUTH`). It forwards every inbound frame
to the test process as `{:relay_in, decoded}`; `push/2` sends any frame to the
client and `drop/1` closes the socket for reconnect tests. No network, no
external relay, ever.

Two application gates keep the real thing out of the suite, both `false` in
`config/test.exs`:

| Key | Gates |
|---|---|
| `:start_relay_connections` | `Social.Connections.Owner` — without it, no connection is opened for a configured relay |
| `:start_activities_sync` | `MediaCentaur.RelaySync` — without it, nothing subscribes to every `FakeRelay` a test stands up |

`Activities.Publisher` is a pubsub listener, so it is not started under
`:test` either; `publisher_test` starts it by hand.

Tests that need either start it by hand, pointed at a `FakeRelay`.

## Development

Two things stand in for the network on a dev machine: the private relay from
`../social-relay` running in Docker on `ws://127.0.0.1:2173` (v0.7.0 or later
for the profile kind), and a **dev friend** — a second keypair
in `priv/dev-social/friend.nsec` (gitignored) driven from the command line. `just social` prints the walkthrough; `just --list` shows
the recipes.

| Recipe | Does |
|---|---|
| `just social-up npub1…` | Builds the relay image from the sibling repo, writes its allowlist (your npub plus the friend's), starts the container, prints the friend's npub to add under Discovery → Friends. The relay goes under Settings → Social. Re-run to restart. |
| `just social-review movie 603 --name "Sample Movie" --sentiment love --text "try it"` | The friend publishes a kind 32164 event (`--sentiment` and `--text` both optional); it shows up on the Feed and on the friend's card. |
| `just social-watched tv_series 1399 --name "Sample Show" --season 2 --episode 5` | The friend finished an episode (kind 32161). |
| `just social-listing movie 603 --name "Sample Movie"` | The friend wants to watch a title (kind 32163). |
| `just social-delete movie 603` / `just social-delete watched tv_series 1399` | The friend withdraws an activity (kind 5; the kind defaults to review); it leaves the row and the friend's card. |
| `just social-feed` | Everything the relay holds — activities and deletions — including what the dev app sent. |
| `just social-status` / `social-down` / `social-reset` | Container state and NIP-11; stop; stop and forget data plus the friend's key. |

The recipes delegate: relay lifecycle to `../social-relay/scripts/dev-relay`
(the relay repo owns its config schema), friend actions to `mix social.dev`,
which loads config without starting the app and speaks to the relay through
`Nostr.OneShot` — a synchronous connect / auth / one action / disconnect
session over `Nostr.Connection`. The friend's title snapshot comes from flags
(`--name`, `--year`, `--poster-path`, `--overview`); nothing calls TMDB.

## Dependencies

Both are pure Elixir — no NIF, nothing added to a user's install footprint.

- `bitcoinex` — secp256k1, BIP-340 Schnorr sign/verify, bech32. Measured at
  ≈3 ms to sign and ≈1.3 ms to verify, which is why the Rustler fallback
  (`ex_secp256k1`) was dropped.
- `mint_web_socket` — the relay socket.
- `{:decimal, "~> 3.0", override: true}` — `bitcoinex` 0.3.0 still requires
  `decimal ~> 1.0 or ~> 2.0`, and every `decimal` below 3.0.0 carries
  GHSA-rhv4-8758-jx7v, which `mix deps.audit` fails on. `bitcoinex` touches
  `Decimal` only in `LightningNetwork.Invoice` (calls unchanged in 3.x) and we
  never call it, so the override beats a vulnerable pin. Drop it when `bitcoinex`
  widens its requirement.

## Scheduled migrations

The watchlist's flat snapshot columns (`name`, `year`, `release_date`,
`poster_path`, `overview`) were superseded by the embedded `TMDB.Title` in
v1.6.0 and dropped in the very next release by
`DropWatchlistFlatColumns`, which runs the inline heal
(`UPDATE watchlist_items SET title = json_object(…) WHERE title IS NULL`, with
the per-line MC0015 carve-out) *before* `remove`-ing them: schema migrations
run before data migrations, so a skipped-release upgrade reaches the drop
before any backfill, and the old release can write flat-only rows in the
seconds between `migrate` and restart. The backfill data migration tolerates
the columns being gone. Nothing is scheduled now.

The `show_watchlist` → `show_discovery` Settings rename is a data migration
(`priv/repo/data_migrations/20260902150000_rename_show_watchlist_settings_key.exs`).
