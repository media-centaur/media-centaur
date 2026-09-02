# Social (contributor guide)

**Social** is the subsystem that connects one install to friends' installs over
Nostr relays: this install's identity, its relays, its friends, and the
recommendations that travel between them. A **friend** is one roster entry
inside it. How it is put together: four contexts, one protocol library, one
long-lived WebSocket per relay, and a sync loop that keeps stored
recommendations in step with what the relays hold.

End-user setup lives on the wiki:
[Social](https://github.com/media-centaur/media-centaur/wiki/Social).
Design rationale and the build order live in
[`docs/superpowers/specs/2026-09-02-friends-recommendations-design.md`](superpowers/specs/2026-09-02-friends-recommendations-design.md)
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
`Discovery ← (nothing) → Recommendations → Social → Nostr`.

| Context | Owns | Depends on |
|---|---|---|
| `MediaCentaur.Nostr` | The protocol and nothing else: `Keys`, `Event`, `Filter`, `Connection`. No tables, no domain meaning. | — |
| `MediaCentaur.Social` | The network's *configuration*: `Identity` (the keypair), `Relay` (`relays` table), `Friend` (`friends` table), and `Connections` (one live connection per relay). | `Nostr` |
| `MediaCentaur.Recommendations` | The *content*: `recommendations` table, `Translation` (events ↔ rows), `Sync` (relays ↔ rows). | `Social`, `Nostr`, `TMDB`, `TmdbArtwork` |
| `MediaCentaur.Discovery` | The watchlist (`watchlist_items`). Knows nothing about the friend network — a row from the feed stores a bare `recommendation_id`. | `Library`, `TmdbArtwork`, `TMDB` |

The Discovery/Recommendations separation is deliberate: a watchlist row records
*intent*, a recommendation records *what a signed event said*. Joining them (who
recommended a watchlist row, whether a feed row is already saved) is the web
layer's job — see [Web layer](#web-layer).

## Identity and secrets

`Social.Identity` holds one secp256k1 keypair. The secret is a single
**sensitive Settings config key**, `nostr_secret_key` (hex, wrapped in
`MediaCentaur.Secret` at rest and in memory); the public key is derived on every
read rather than stored, so the two can never disagree.

- `ensure/0` generates on first use. Two callers: the Settings page's Social section, and
  `Recommendations.recommend/2` — a user can recommend a title before ever
  opening the tab, which mints the identity right there.
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
nothing about what an event means. Statuses are `:connecting`, `:connected`,
`:disconnected`, `:auth_failed`.

The owner (the pid passed as `owner`) receives `{:nostr, url, message}` — see the
`Nostr.Connection` moduledoc for the full message list. Behaviour worth knowing
before touching it:

- **Subscriptions live in the connection's state** and are re-issued after every
  reconnect *and* after a successful `AUTH` — an allowlist relay refuses `REQ`
  before authenticating.
- **Backoff** doubles from 1 s to 60 s and resets on connect. Mint's own connect
  timeout is capped at 5 s so an unreachable relay doesn't hold the process for
  30.
- **`publish/2`, `subscribe/3`, `unsubscribe/2` are casts** — nothing blocks
  behind a connect attempt.
- **Every inbound frame is type-guarded.** A relay is untrusted input; a frame
  that doesn't match falls to a debug log, never a crash.

`Social.Connections` keeps that population in step with the `relays` table: a
Registry keyed by URL, a DynamicSupervisor, and `Connections.Owner`, which
reconciles on boot and on `RelayAdded` / `RelayRemoved` / `IdentityChanged`,
receives every connection's messages, and re-broadcasts them on
`social:connections`. `Connections.status/0` is the read model —
`%{url => %{state, last_error, since}}` — where `since` is the onset of the
current state, which is what the health probe measures against.

## Event shape

The wire contract — every kind, its tags and content fields, deletion, sync
and what a relay must do — is [`docs/social-protocol.md`](social-protocol.md)
(the wiki's *Social Protocol* page is generated from it). This section is the
implementation view.

`Recommendations.Translation` is the anti-corruption layer, and it is pure in
both directions.

| Field | Value |
|---|---|
| Kind | `32160` (addressable) |
| `d` tag | `tmdb:<media_type>:<tmdb_id>` |
| Content | JSON — `{"title": <TMDB.Title fields>, "note": string \| null}` |
| `p` tag | Defined by the spec for directed recommendations; never set today |

Addressable means the relay keeps one event per `(author, d)`, so recommending
the same title twice replaces rather than appends. The row mirrors that: identity
is `(author_pubkey, tmdb_id, media_type)`, `recommended_at` decides, and the
embedded title uses `on_replace: :delete` — the newer event's snapshot is the
whole truth, never a field-wise merge.

`from_event/1` shape-checks an already-*verified* event; the address and the
content snapshot must agree on identity, and a mismatch is rejected rather than
reconciled. `raw_event` keeps the signed wire form so the event can be
republished to a relay that lacks it. Sent vs received is derived by comparing
`author_pubkey` against the identity — no stored direction column can disagree
with the signature.

Note length is capped at 500 characters (`Recommendations`), matched by the
textarea's `maxlength`.

## Sync

`Recommendations.Sync` is a GenServer over `social:connections` and
`social:updates`:

1. `:connected` for a relay → subscribe `"feed"` (authors = friends ++ self,
   kind 32160) and `"own:<url>"` (authors = [self]) on that relay, and reset the
   seen-set for that URL.
2. `{:event, sub_id, event}` → `Recommendations.ingest/1` (verify signature,
   require a known author, newest wins). Events on `"own:<url>"` also record
   their id in the seen-set.
3. `{:eose, "own:<url>"}` → publish to that relay every stored own event it did
   *not* send. A per-relay diff, not a blanket re-publish: addressable events are
   few, and a relay that already holds one doesn't need it again.
4. A roster change on `social:updates` resubscribes `"feed"` on every relay with
   the new author list.

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
| `recommendations:updates` | `Recommendations.Events` | `{:recommendation_received, _}`, `{:recommendation_sent, _}` |

Subscribers use `Social.subscribe/0`, `Social.subscribe_connections/0` and
`Recommendations.subscribe/0`. Payloads are typed structs per ADR-060.

`Connections.apply_message/2` is the owner's own fold over a connection message,
exported so a LiveView folding `social:connections` into local state can never
disagree with the owner about what a message meant.

## Web layer

`MediaCentaurWeb.DiscoveryLive` is one LiveView with a `live_action` per tab
(`:feed` at `/discovery`, `:watchlist`, `:friends`). The Friends tab's block is
iteration-phase function components under `live/discovery_live/`
(`identity_block`, `relay_block`, `roster_block`, `feed_row`, `recommend_modal`)
— no stories and no input-system support yet; the hardening pass moves them under
`components/` (spec decision 11), which is when MC0009 starts applying.

The joins the contexts may not make happen here:

- **Feed rows** — `Recommendations.list_feed/0` returns the record plus the
  friend's nickname (`own?: true`, `nickname: nil` for this identity's own).
  `DiscoveryLive` adds `poster_url`, `library_owner_id`
  (`Library.ExternalIds.tmdb_owners/1`) and `on_watchlist?`
  (`Discovery.watchlisted_refs/0`).
- **Watchlist rows** — the row stores only `recommendation_id`; the page resolves
  it to a nickname through `Recommendations.get_many/1` → `Social.list_friends/0`.

`MediaCentaurWeb.Live.RecommendFlow` is the shared modal flow (`use RecommendFlow`
injects the handlers), hosted by `DiscoveryLive` for watchlist rows and by any
`EntityModal` host for the library detail page. The detail page's Recommend
control is gated on the `show_discovery` preference
(`Settings.Preferences.DiscoveryVisibility`), the same preference that gates the
sidebar entry; watchlist rows need no gate because that page is Discovery already.

## Health

`Social.IncidentContext` is the `assess/0` the `ErrorReports.Evaluator` polls
(ADR-054), owning one `:subsystem` incident for the `friends` component. Its
faults are `:relay_auth_failed` (error, no grace), `:relays_unreachable` (error,
after a 180 s grace) and `:relay_degraded` (warning). No relays configured is
never a fault. The decision is the pure `decide/3`; `assess/0` is the shell.

**Known gap:** `:subsystem` incidents don't reach the health board.
`BucketCache.from_incidents/1` keeps only fingerprint-keyed (`:log`) rows, so the
Social tile reads "No issues" with every relay down. Pre-existing and
system-wide (the download-client and search probes have it too); fixing it is an
`ErrorReports` change. The Status widget
(`Components.StatusWidgets.Social`) still shows the live summary in the
drill-in.

Console tags: `:nostr` for the wire (`Nostr.Connection`), `:social` for
everything above it (`Social`, `Recommendations`). `HealthBoard.normalize/1`
aliases `:nostr` incidents onto the Social tile; `:subsystem` incidents (the assessor's own
faults) still never reach the board — a pre-existing ErrorReports gap.

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
| `:start_recommendations_sync` | `Recommendations.Sync` — without it, nothing subscribes to every `FakeRelay` a test stands up |

Tests that need either start it by hand, pointed at a `FakeRelay`.

## Development

Two things stand in for the network on a dev machine: the private relay from
`../social-relay` running in Docker on `ws://127.0.0.1:2173`, and a **dev
friend** — a second keypair in `priv/dev-social/friend.nsec` (gitignored) driven
from the command line. `just social` prints the walkthrough; `just --list` shows
the recipes.

| Recipe | Does |
|---|---|
| `just social-up npub1…` | Builds the relay image from the sibling repo, writes its allowlist (your npub plus the friend's), starts the container, prints the friend's npub to add under Discovery → Friends. The relay goes under Settings → Social. Re-run to restart. |
| `just social-recommend movie 603 --name "Sample Movie" --note "try it"` | The friend publishes a kind 32160 event; it shows up in your Feed. |
| `just social-feed` | Everything the relay holds, including what the dev app sent. |
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
`poster_path`, `overview`) are superseded by the embedded `TMDB.Title` and
**must be dropped in the release immediately after the one that shipped the
embed**. The drop migration has to run the inline heal
(`UPDATE watchlist_items SET title = json_object(…) WHERE title IS NULL`, with
the per-line MC0015 carve-out) *before* `remove`-ing the columns: schema
migrations run before data migrations, so a skipped-release upgrade reaches the
drop before any backfill, and the old release can write flat-only rows in the
seconds between `migrate` and restart. Until it lands, such a row crashes
`/discovery/watchlist` on mount.

The `show_watchlist` → `show_discovery` Settings rename is a data migration
(`priv/repo/data_migrations/20260902150000_rename_show_watchlist_settings_key.exs`).
