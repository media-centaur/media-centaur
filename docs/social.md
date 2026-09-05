# Social (contributor guide)

**Social** is the subsystem that connects one install to friends' installs over
Nostr relays: this install's identity, its relays, its friends, and the
activities that travel between them — a title recommended, watched, or
tracked. A **friend** is one roster entry inside it. How it is put together:
four contexts, one protocol library, one long-lived WebSocket per relay, and
a sync loop that keeps stored activities in step with what the relays hold.

End-user setup lives on the wiki:
[Social](https://github.com/media-centaur/media-centaur/wiki/Social).
Design rationale and the build order live in
[`docs/superpowers/specs/2026-09-02-friends-recommendations-design.md`](superpowers/specs/2026-09-02-friends-recommendations-design.md),
[`docs/superpowers/specs/2026-09-05-social-activity-feed-design.md`](superpowers/specs/2026-09-05-social-activity-feed-design.md)
and [`campaigns/friends-recommendations.md`](../campaigns/friends-recommendations.md).

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

Four `Boundary` contexts, each with one job. The dependency edges run one way:
`Discovery ← (nothing) → Activities → Social → Nostr`; `Activities` also
reads `Library`, `WatchHistory`, `ReleaseTracking` and `Settings.Preferences`
to turn a person's acts into activities.

| Context | Owns | Depends on |
|---|---|---|
| `MediaCentaur.Nostr` | The protocol and nothing else: `Keys`, `Event`, `Filter`, `Connection`. No tables, no domain meaning. | — |
| `MediaCentaur.Social` | The network's *configuration*: `Identity` (the keypair), `Relay` (`relays` table), `Friend` (`friends` table), and `Connections` (one live connection per relay). | `Nostr` |
| `MediaCentaur.Activities` | The *content*: `activities` table, `Translation` (events ↔ rows), `Sync` (relays ↔ rows), `Publisher` (a person's acts → activities, behind the sharing toggles). | `Social`, `Nostr`, `TMDB`, `TmdbArtwork`, `Library`, `WatchHistory`, `ReleaseTracking`, `Settings.Preferences` |
| `MediaCentaur.Discovery` | The watchlist (`watchlist_items`). Knows nothing about the friend network — a row from the feed stores a bare `activity_id`. | `Library`, `TmdbArtwork`, `TMDB` |

The Discovery/Activities separation is deliberate: a watchlist row records
*intent*, an activity records *what a signed event said*. Joining them (who
recommended a watchlist row, whether a feed row is already saved) is the web
layer's job — see [Web layer](#web-layer).

## Identity and secrets

`Social.Identity` holds one secp256k1 keypair. The secret is a single
**sensitive Settings config key**, `nostr_secret_key` (hex, wrapped in
`MediaCentaur.Secret` at rest and in memory); the public key is derived on every
read rather than stored, so the two can never disagree.

- `ensure/0` generates on first use. Two callers: the Settings page's Social section, and
  `Activities` publishing an own activity — a user can recommend a title before
  ever opening the tab, which mints the identity right there.
- `import_nsec/1` is the only replacement path (two-click arm in the UI,
  MC0027 treatment b).
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
| `32160` | Recommendation | `tmdb:<media_type>:<tmdb_id>` | `sentiment` (`like` / `love`, absent = like), `note`, `recommended_at` |
| `32161` | Watched | same | `watched_at`, `episode` (TV: `season_number`, `episode_number`, `name`) |
| `32162` | Tracking | same | `tracked_at` |

A `p` tag is defined by the spec for directed recommendations and never set.

Addressable means the relay keeps one event per `(author, kind, d)`, so
recommending the same title twice — or finishing the next episode — replaces
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

Note length is capped at 500 characters (`Activities`), matched by the
textarea's `maxlength`. Content carries `"v": 1`; `from_event/1` treats an
absent `v` as 1 and drops an unknown one.

**Producers.** Recommending is an explicit act and always publishes
(`Activities.recommend/3`, from the Recommend modal, with the sentiment
the sender picked). Watched and tracking
activities come from `Activities.Publisher`, a pubsub listener over
`watch_history:events` and `release_tracking:updates` that calls
`Activities.watched/2` / `tracking/1` only while the `share_watched` /
`share_tracking` preference is on (Settings → Social → Sharing, both default
off). A completion resolves its TMDB identity through `Library.ExternalIds`;
an entity without one, and every extra, is skipped. Only a `source: :manual`
tracking item broadcasts `ReleaseTracking.Events.TrackingStarted` — the
library scan's items never become activities.

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
`recommended_at` / `watched_at` / `tracked_at` in the content, a `deleted_at`
tag on the deletion — and is what `acted_at` / `deleted_at` on the row hold,
so ordering and display never move when a message is re-signed or arrives
late. A message without
its domain time gets the wire time as fallback.

**Stamping.** A relay keeps one record per address and, on a `created_at` tie,
keeps what it holds (a deletion beating an activity). So a new own activity is
stamped strictly after the activity or tombstone the row already holds, and
`delete/1` stamps the deletion no earlier than the activity it withdraws
(`Activities.stamp/3`, private). Without this
a same-second re-recommendation would replace the row here, be discarded by
the relay, and be republished by the own-events diff on every connect.

## Sync

`Activities.Sync` is a GenServer over `social:connections` and
`social:updates`:

1. `:connected` for a relay → subscribe `"feed"` (authors = friends ++ self,
   kinds 32160, 32161, 32162 + 5, `limit` 500, no `since`) and `"own:<url>"`
   (authors = [self], same kinds) on that relay, and reset the seen-set for
   that URL.
2. `{:event, "feed", event}` → `Activities.ingest/1` (verify signature,
   require a known author, newest wins, deletions tombstone). Events on
   `"own:<url>"` also record their id in the seen-set.
3. `{:eose, "feed"}` → a full page asks for the next (`until` = oldest − 1);
   the first short page after paging re-issues `"feed"` live.
4. `{:eose, "own:<url>"}` → publish to that relay every stored own event it did
   *not* send — activities of live rows, deletions of withdrawn ones. A
   per-relay diff, not a blanket re-publish.
5. A roster change on `social:updates` resubscribes `"feed"` on every connected
   relay with the new author list.

There is no sync cursor: every connect reads the relay from the start. A relay
holds one record per signer per title, so the whole history is a page, and a
`since` keyed on `created_at` skipped an event published late with an older
stamp (a withdrawal made offline). Re-reading is idempotent.
6. `{:ok, id, false, reason}` → a warning naming what the relay refused
   (`Activities.own_event_kind/1`: "rejected a deletion: …" / "rejected a
   recommendation: …" / "rejected a watched activity: …"). The publisher owns
   the wording; `Connections` only keeps the reason as the relay row's last
   error. A relay refusing a deletion with `blocked: kind 5 is not stored by
   this relay` is a `social-relay` older than v0.3.0; one refusing kind 32161
   or 32162 is older than v0.4.0 — and, because its deletion parser only
   knows a 32160 coordinate, that relay refuses the *deletion* of a watched
   or tracking activity with `blocked: only the author may delete an event`.
   Both are re-sent on every connect until it is upgraded.

`ingest/1` rejects anything not signed by the identity or a key on the roster, so
a relay that hands over the whole world still yields only what you follow.

On reconnect, `Connections.Owner` re-applies the relay's registered subscriptions
as well, so `"feed"` and `"own:<url>"` each go out twice. That is harmless
(relays de-duplicate identical subs, and the seen-set resets on `:connected`) and
is left alone rather than adding a seam to silence one sender.

## PubSub topics

All three are declared in `MediaCentaur.Topics`.

| Topic | Publisher | Messages |
|---|---|---|
| `social:updates` | `Social.Events` | `{:identity_changed, _}`, `{:relay_added, _}`, `{:relay_removed, _}`, `{:friend_added, _}`, `{:friend_removed, _}` |
| `social:connections` | `Social.Connections.Owner` | `{:relay_connection, url, message}` — the re-broadcast of every `Nostr.Connection` owner message |
| `activities:updates` | `Activities.Events` | `{:activity_received, _}`, `{:activity_sent, _}`, `{:activity_deleted, _}` — each payload carries the activity's `kind` |

Subscribers use `Social.subscribe/0`, `Social.subscribe_connections/0` and
`Activities.subscribe/0`. Payloads are typed structs per ADR-060.

`Connections.apply_message/2` is the owner's own fold over a connection message,
exported so a LiveView folding `social:connections` into local state can never
disagree with the owner about what a message meant.

## Web layer

`MediaCentaurWeb.DiscoveryLive` is one LiveView with a `live_action` per tab
(`:feed` at `/discovery`, `:watchlist`, `:friends`). The Feed tab has an
Incoming / Yours scope (`feed_scope` assign; the tab badge counts incoming
only), every row leads with who did what (`DiscoveryLive.ActivityWords`:
"recommended", "watched S02E05", "started tracking"), and own rows carry
Delete → `Activities.delete/1`.
The tab's pieces are iteration-phase function components under
`live/discovery_live/` (`roster_block`, `feed_row`, `recommend_modal`) — no
stories and no input-system support yet; the hardening pass moves them under
`components/` (spec decision 11), which is when MC0009 starts applying.

Who recommended a title, and how much, is one component everywhere —
`Components.Discovery.RecommendationPennant` — fed by
`Activities.recommendations_for/1` on the watchlist rows, the Incoming
search rows and both detail modals, and by the row itself on the Feed. See
`docs/plans/2026-09-05-recommendation-pennant.md` for the decisions.

The joins the contexts may not make happen here:

- **Feed rows** — `Activities.list_feed/0` returns the record plus the
  friend's nickname (`own?: true`, `nickname: nil` for this identity's own).
  `DiscoveryLive` adds `poster_url`, `library_owner_id`
  (`Library.ExternalIds.tmdb_owners/1`) and `on_watchlist?`
  (`Discovery.watchlisted_refs/0`).
- **Watchlist rows** — the row stores only `activity_id`; the page resolves
  it to a nickname through `Activities.get_many/1` → `Social.list_friends/0`.

`MediaCentaurWeb.Live.RecommendFlow` is the modal flow (`use RecommendFlow`
injects the handlers), hosted by every `EntityModal` host for the library detail
page — the only place a recommendation is made. The sharing toggles live in
`SettingsLive.SocialSection`. The Recommend control is gated
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
everything above it (`Social`, `Activities`). `HealthBoard.normalize/1`
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
| `:start_activities_sync` | `Activities.Sync` — without it, nothing subscribes to every `FakeRelay` a test stands up |

`Activities.Publisher` is a pubsub listener, so it is not started under
`:test` either; `publisher_test` starts it by hand.

Tests that need either start it by hand, pointed at a `FakeRelay`.

## Development

Two things stand in for the network on a dev machine: the private relay from
`../social-relay` running in Docker on `ws://127.0.0.1:2173` (v0.4.0 or later
for the watched and tracking kinds), and a **dev friend** — a second keypair
in `priv/dev-social/friend.nsec` (gitignored) driven from the command line. `just social` prints the walkthrough; `just --list` shows
the recipes.

| Recipe | Does |
|---|---|
| `just social-up npub1…` | Builds the relay image from the sibling repo, writes its allowlist (your npub plus the friend's), starts the container, prints the friend's npub to add under Discovery → Friends. The relay goes under Settings → Social. Re-run to restart. |
| `just social-recommend movie 603 --name "Sample Movie" --note "try it"` | The friend publishes a kind 32160 event; it shows up in your Feed. |
| `just social-watched tv_series 1399 --name "Sample Show" --season 2 --episode 5` | The friend finished an episode (kind 32161). |
| `just social-tracking movie 603 --name "Sample Movie"` | The friend started tracking a release (kind 32162). |
| `just social-delete movie 603` / `just social-delete watched tv_series 1399` | The friend withdraws an activity (kind 5); the row leaves your Feed. |
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
