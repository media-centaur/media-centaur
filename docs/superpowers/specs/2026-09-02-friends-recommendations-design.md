# Friends & recommendations (Nostr backbone) — design

Date: 2026-09-02
Status: approved (design); implementation not started
Campaign: `campaigns/friends-recommendations.md`

## Glossary

Terms are defined here before first use. Code names are in backticks.

- **Identity** — the user's secp256k1 keypair. Displayed as an **npub**
  (bech32-encoded public key); exported and imported as an **nsec**
  (bech32-encoded secret key). One identity per install.
- **Relay** — a Nostr WebSocket server that stores and forwards events. The
  user configures a list of relay URLs. A **private relay** is one the
  friend group self-hosts with a pubkey allowlist; a **public relay** is
  anyone's. The app treats both identically.
- **Connection** — the app's live WebSocket session to one relay.
- **Friend** — a public key the user follows, with a locally assigned
  **nickname**. Friends are the only authors the feed accepts.
- **Recommendation** — one signed Nostr event stating "this title, from me,
  with an optional note." Sent recommendations are the user's own; received
  recommendations are friends'.
- **Feed** — the received recommendations, newest first, on the Discovery
  page.
- **Watchlist** — the existing local list of title-level viewing intent
  (`MediaCentaur.Discovery`).
- **Discovery page** — the main-navigation page that hosts the Feed, the
  Watchlist and Friends as three tabs. Replaces the Watchlist page.
- **Friends tab** — the Discovery tab where the identity, the relay list and
  the friend roster are managed. Not a Settings section.
- **Title** — the app-wide TMDB title snapshot: identity (`tmdb_id`,
  `media_type`) plus render fields. `MediaCentaur.TMDB.Title`.
- **Addressable event** — a Nostr event kind in the 30000–39999 range: relays
  keep only the newest event per (author, kind, `d` tag).

## Purpose

Let a user have friends and send/receive title recommendations inside the
app, with no server we operate. Selecting a received recommendation puts the
title on the watchlist, whose existing pursue hand-off triggers acquisition
after the usual human confirm. Private-first: the first deployment target is
a friend group's self-hosted allowlist relay; public relays are supported as
additional entries.

## Decisions

Carried from the campaign file (2026-06-17 / 2026-08-18): no central server;
protocol = Nostr; identity = keypair; broadcast-first, directed-capable;
reuse the acquisition path; watchlist foundation shipped v1.0.0.

Made in this session (2026-09-01 / 02):

1. **Payload = title snapshot + optional note.** No "where to start", no
   reactions. Both are additive later.
2. **Received recommendations are a feed the user browses.** Adding one to the
   watchlist is the user's act. Nothing auto-lands.
3. **Discovery page with tabs.** The Watchlist page becomes the Discovery page
   with Feed, Watchlist and Friends tabs. Later discovery sources join it.
   Friends is a product surface that will keep evolving, so it lives here
   rather than in Settings.
4. **Private first.** No default relay list ships. The user pastes their
   group's relay URL; public relays are more entries. The client speaks
   NIP-42 relay authentication so an allowlist relay can gate reads and
   writes by pubkey. The self-hosted relay itself is a separate repository
   in the GitHub organization and is out of scope here.
5. **Key management: generate silently, export on demand.** The keypair is
   created when the Friends tab is first opened. Settings shows
   the npub with a copy control; "Export secret key" and "Import secret key"
   live behind a disclosure. No passphrase.
6. **Friend = pasted npub + typed nickname.** No profile events. Names are
   local.
7. **Recommend action on library detail modals and watchlist rows** only.
8. **Transport = one long-lived connection per relay.** Not polling.
9. **No native dependency.** `bitcoinex` (pure Elixir, maintained, dep only
   `decimal`) provides BIP-340 Schnorr and bech32. Measured on the owner's
   machine: sign ≈ 3 ms, verify ≈ 1.3 ms. Feed volume is a few events per day
   per friend. `ex_secp256k1` (Rustler) is the fallback only if verification
   becomes a measured problem.
10. **Thin in-house Nostr client** over `mint_web_socket`. The hex packages
    `nostr` and `nostr_basics` are unmaintained since 2023.
11. **Iterate light, harden after.** The UI will change a lot. During
    iteration the new pieces (feed row, friend row, relay row, identity
    block, recommend modal) are function components inside the Discovery
    LiveView's own directory (`lib/media_centaur_web/live/discovery_live/`),
    where the storybook check (MC0009) does not apply. A scheduled
    **hardening pass** moves them under `lib/media_centaur_web/components/`
    with stories and adds keyboard/gamepad navigation. No input-system
    support in the first iteration.
12. **Own Status section.** The Status page gains a Friends section: health
    and aggregates only (per-relay connection state, friend count, last
    received recommendation time), with a link to the Friends tab.

## Unification decisions (unify_design pass — adjudicated, follow as written)

Core idea: a TMDB title reference is a first-class value; search hits,
tracked items, watchlist items and recommendations are that value plus a
surface-specific wrapper. A recommendation is a signed statement about that
value by an identity the user trusts.

1. **`MediaCentaur.TMDB.Title` replaces `ReleaseTracking.TitleResult`.** The
   convergence scheduled in the watchlist plan fires now (this campaign is
   Discovery's first candidate source). `Title` is an Ecto embedded schema:
   `tmdb_id`, `media_type` (`:movie | :tv_series`), `name`, `year`,
   `release_date`, `poster_path`, `backdrop_path`, `overview`. It carries no
   per-surface decoration. TMDB title search (`search_tmdb/1` and the
   movie/tv fallbacks) moves from `ReleaseTracking.Acquisition` into the
   TMDB context and returns `[Title.t()]`. ReleaseTracking, Discovery and
   Recommendations depend on `MediaCentaur.TMDB` for the struct;
   `Discovery.add_to_watchlist/1` and
   `ReleaseTracking.track_from_search_async/1` accept `%Title{}` instead of
   plain attrs.
2. **`tracked?` leaves the struct.** It becomes a web-layer decoration via the
   same MapSet-attr mechanism `watchlisted?`/`in_library?` already use
   (`tracked_refs`). The Incoming page's row patch on track becomes a ref-set
   update.
3. **Rows embed the title.** `watchlist_items` and `recommendations` keep
   `tmdb_id` and `media_type` as indexed columns and `embeds_one :title,
   TMDB.Title`. The changeset derives the two columns from the embed, so
   there is one write path and one read path (`row.title`). The watchlist
   migration is paired: add the embed column, backfill it idempotently from
   the flat columns, drop the flat snapshot columns (`name`, `year`,
   `release_date`, `poster_path`, `overview`) in a later release per the
   safe-migration rule.
4. **One title component.** `MediaCentaurWeb.Components.TMDB.TitleSummary`
   (`title_summary/1`) renders poster, name, year and optional overview from
   a `Title` plus a resolved `poster_url`. Search rows, watchlist rows and
   feed rows use it now. The plan modal's selection header converges when it
   is next touched (named here; not an orphan).
5. **One poster ladder.** A web-layer helper resolves a `Title`'s poster:
   cached artwork tier first (`TmdbArtwork.urls/2`), TMDB hotlink fallback.
   Search rows and watchlist rows both use it (search rows only hotlink
   today).
6. **Artwork holds.** `Recommendations.TmdbArtworkHolds` implements
   `TmdbArtwork.HoldProvider` and is registered alongside the Discovery
   provider: a feed row is standing interest.
7. **Feature gate renamed.** `show_watchlist` becomes `show_discovery`
   (`Settings.Preferences.DiscoveryVisibility`), gating the sidebar entry,
   the Discovery page, the modal watchlist toggle, the modal Recommend
   action, and the Incoming search-row bookmark. A settings-row migration
   renames the stored key. Default stays off until the feature settles.
8. **Shared tab strip.** `MediaCentaurWeb.Components.TabStrip`
   (`tab_strip/1`) is extracted from `review_tabs`; Review and Discovery
   both use it.
9. **Recommend action follows the modal's shared-handler pattern.** Like
   `modal_watchlist_toggle`, the event and its handler live in `EntityModal`
   so every modal host gets it structurally.
10. **Not a duplicate, left alone.** `ReleaseTracking.Item.name` is a label
    on a tracking record that refreshes itself from TMDB, not a render
    snapshot.

Cost accepted by the owner 2026-09-02: roughly one extra session on a five to
six session build.

## Architecture

Four units, single responsibility each. Boundary declarations are the
canonical dependency list.

### `MediaCentaur.TMDB.Title`

Embedded schema (above). Lives in the TMDB context, which owns no domain
data; the struct is a value type. `Title.changeset/2` validates identity and
`name`.

### `MediaCentaur.Nostr` — protocol only

`use Boundary, deps: []`. Knows nothing about recommendations or friends.

- `Nostr.Keys` — generate a secret key; derive the x-only public key; encode
  and decode `npub`/`nsec` (bech32 via `bitcoinex`); hex helpers. Secret
  keys are `MediaCentaur.Secret`-wrapped at every boundary.
- `Nostr.Event` — struct (`id`, `pubkey`, `created_at`, `kind`, `tags`,
  `content`, `sig`); NIP-01 canonical serialization; `id/1`; `sign/2` (event,
  secret) and `verify/1` (recomputes the id and checks the Schnorr
  signature); JSON encode/decode.
- `Nostr.Connection` — one GenServer per relay URL over `mint_web_socket`.
  Started with `url`, a `signer` (fun that signs an event with the identity,
  used for NIP-42), and an `owner` pid that receives
  `{:nostr, url, message}` for `:connected`, `:disconnected`,
  `{:event, sub_id, event}`, `{:eose, sub_id}`, `{:ok, event_id, accepted?,
  reason}`, `{:auth_required, reason}`. API: `publish/2`, `subscribe/3`
  (sub id + filters), `unsubscribe/2`, `status/1`. Handles the NIP-42 `AUTH`
  challenge by signing a kind 22242 event; reconnects with capped
  exponential backoff; resubscribes after reconnect.
- `Nostr.Filter` — filter map builder (`authors`, `kinds`, `#d`, `since`,
  `limit`).

### `MediaCentaur.Friends` — network configuration

`use Boundary, deps: [MediaCentaur.Nostr, MediaCentaur.Settings]`,
`exports: [Friend, Relay, Identity, Events]`.

- `Friends.Identity` — reads/creates the identity. The secret key is stored
  under the new sensitive Settings key `nostr_secret_key`; the public key is
  derived. `ensure/0` (generate on first use), `npub/0`, `export_nsec/0`,
  `import_nsec/1` (replaces the identity; broadcasts `identity_changed`).
- `Friends.Friend` — schema `friends`: `pubkey` (hex, unique), `nickname`
  (required). `add_friend/1` accepts an npub or hex plus nickname;
  `remove_friend/1`; `list_friends/0`; `friend_by_pubkey/1`.
- `Friends.Relay` — schema `relays`: `url` (unique, `wss://` or `ws://`).
  `add_relay/1`, `remove_relay/1`, `list_relays/0`. Connection state is
  runtime, never a column.
- `Friends.Connections` — DynamicSupervisor plus a registry owner process
  that starts one `Nostr.Connection` per relay row at boot, starts/stops
  connections on relay add/remove, and exposes `status/0`
  (`%{url => :connected | :connecting | :disconnected | :auth_failed}`) for
  the Friends tab and the Status section. It is the `owner` of every connection and re-broadcasts
  connection messages on PubSub topic `friends:connections`.
- PubSub topic `friends:updates` for roster, relay and identity changes.

### `MediaCentaur.Recommendations` — content

`use Boundary, deps: [MediaCentaur.Nostr, MediaCentaur.Friends,
MediaCentaur.TMDB, MediaCentaur.TmdbArtwork]`, `exports: [Recommendation,
Events, TmdbArtworkHolds]`.

- `Recommendations.Recommendation` — schema `recommendations`: `event_id`
  (hex, unique), `author_pubkey` (hex), `tmdb_id`, `media_type`,
  `embeds_one :title, TMDB.Title`, `note` (nullable), `recommended_at`
  (event `created_at`, utc), `raw_event` (the signed event JSON, for
  republish and audit), timestamps. Unique index on `(author_pubkey,
  tmdb_id, media_type)`: a newer event for the same address replaces the
  row. Sent vs received is derived by comparing `author_pubkey` with the
  identity.
- `Recommendations.Translation` — the anti-corruption layer. `to_event/3`
  (title, note, identity) builds the unsigned event; `from_event/1` parses a
  verified event into recommendation attrs or `{:error, reason}` on malformed
  content.
- `Recommendations.Sync` — one process, owner-side consumer of
  `friends:connections`. On `:connected` for a relay: subscribe with
  `authors = friends ++ [self]`, `kinds = [@kind]`; then request the relay's
  view of the user's own events (`authors = [self]`) and publish any own
  recommendation the relay lacks (compare `event_id`s after `EOSE`). On
  friends-roster change: resubscribe on every connection. On identity change:
  the `friends:updates` broadcast restarts connections (new signer) and Sync
  resubscribes.
- Inbound: `{:event, _, event}` → `Nostr.Event.verify/1` → author must be a
  friend or self → `Translation.from_event/1` → upsert (only if newer than
  the stored row for the address) → broadcast `recommendation_received` on
  `recommendations:updates`.
- Outbound: `recommend(title, note)` builds, signs, persists (upsert on the
  address) and publishes to every connected connection. Disconnected relays
  receive it on their next `:connected` sync. Broadcasts
  `recommendation_sent`.
- `list_feed/0` — received recommendations newest first, each decorated with
  the friend nickname, on-watchlist and in-library state; `list_sent/0`.
- `Recommendations.TmdbArtworkHolds` — hold provider over all rows.

### Discovery changes

- `WatchlistItem.source` gains `:friend`; new nullable `recommendation_id`
  (UUID, no FK across contexts — plain reference, resolved at read time).
- `add_to_watchlist/1` takes `%Title{}` plus optional `source` and
  `recommendation_id`.
- Discovery and Recommendations do not depend on each other. The web layer
  joins them: the Watchlist tab loads the watchlist and, for rows carrying a
  `recommendation_id`, asks `Recommendations` for the recommending nickname.

## Event shape

Kind **32160** (addressable; unassigned in the NIPs registry as of
2026-09-02). Tags:

- `["d", "tmdb:<media_type>:<tmdb_id>"]` — the address, e.g. `tmdb:movie:603`.
- `["p", "<recipient pubkey>"]` — defined, never set in this slice
  (directed-capable seam).

Content: JSON object `{"title": {...Title fields...}, "note": "..." | null}`.
The title snapshot rides in the event so receivers render without a TMDB
call. `poster_path`/`backdrop_path` are TMDB paths, not URLs.

Validation on receipt: kind matches, `d` tag parses, content title identity
matches the `d` tag, `name` present. Anything else is dropped and logged at
debug under the `:recommendations` component tag.

## Runtime behavior

- Boot: `Friends.Connections` starts a connection per relay row; if no
  identity exists, no connections start (nothing to sign with) and the
  Friends tab explains this.
- Connect → optional `AUTH` challenge signed with the identity → subscribe
  → outbound sync → live events. Reconnect on drop with backoff; the
  subscription is re-issued.
- Sending with zero connected relays persists locally; the recommend modal
  shows the relay state inline so the user knows delivery is pending.
- Relay `OK` with `accepted? = false` is logged at warning with the relay's
  reason (allowlist rejections surface here) and shown on the Friends tab
  and the Status section as the relay's last error.

## UI

- **Discovery page** at `/discovery` (Feed), `/discovery/watchlist` and
  `/discovery/friends`. Sidebar entry "Discovery", gated by `show_discovery`.
  The old `/watchlist` route is removed. `tab_strip` joins the three tabs
  (Feed and Watchlist with counts).
- **Feed tab** rows: `title_summary` + "from <nickname> · <relative time>"
  + note. Actions: "Add to watchlist" (becomes an "On watchlist" state), "In
  library" marker when present. Own recommendations appear with "You".
  Empty state names the two prerequisites plainly when missing (no relay,
  no friends).
- **Friends tab**, three blocks:
  - Identity: npub with copy control; disclosure with "Export secret key"
    (reveals nsec with a plain warning) and "Import secret key" (textarea +
    confirm). Copy states that recommendations are visible to anyone who can
    read the configured relays.
  - Relays: list with per-relay status and last error; add by URL; remove.
  - Friends: list with nickname and shortened npub; add by npub + nickname;
    remove.
- **Recommend modal**: opened from the library detail modal (`Recommend`
  next to the watchlist toggle) and from watchlist rows. Optional note,
  relay state line, Send. Re-recommending replaces the earlier event.
- **Status page, Friends section**: per-relay connection state and last
  error, friend count, sent/received counts, last received time; a link to
  the Friends tab. No lists that duplicate the tab.
- Settings gains nothing beyond the renamed `show_discovery` preference.
- All new UI pieces are function components under
  `lib/media_centaur_web/live/discovery_live/` during iteration (decision
  11); the shared `title_summary` and `tab_strip` are proper components
  with stories from the start because they replace existing rendering.
- No keyboard/gamepad navigation in the first iteration (decision 11).

Copy passes through the `writing-copy` skill; "entry" for titles in user
copy, never "entity".

## Error handling and observability

- All logging through `MediaCentaur.Log` with component tags `:nostr`,
  `:friends`, `:recommendations`.
- Connection state is visible on the Friends tab and the Status page's
  Friends section.
- Malformed or unverifiable events never raise; they are dropped with a
  debug log.
- Secret key never appears in logs: `Secret`-wrapped everywhere except the
  signing call.

## Testing

- `Nostr.Keys` / `Nostr.Event`: BIP-340 published test vectors; NIP-01
  serialization vectors (escaping rules); round-trip npub/nsec.
- `Nostr.Connection`: a test-only in-process relay — a Plug/WebSock handler
  mounted on a test endpoint speaking `EVENT`, `REQ`, `CLOSE`, `AUTH`, `OK`,
  `EOSE` for the subset used. Tests: auth challenge signed, subscribe and
  receive, publish and `OK`, reconnect and resubscribe after the server
  closes.
- `Recommendations.Sync`: against the fake relay — outbound sync publishes
  missing own events; inbound from a non-friend is dropped; a newer address
  replaces; an older one is ignored.
- `Translation`: property-style round trip `to_event` → sign → verify →
  `from_event`.
- LiveView tests: feed rows and actions, recommend modal from both hosts,
  Friends tab (identity create, export/import, relay and friend add/remove),
  Discovery visibility gate, Status section.
- Existing `TitleResult` tests move with the struct; storybook stories for
  `title_summary` and `tab_strip` only in this slice (the rest arrive with
  the hardening pass).
- No network in tests; no real titles in fixtures.

## Out of scope for this slice

Directed recommendations (the `p` tag stays unset), profiles (kind 0),
reactions, a dismissals ledger, relay administration from the app, shipped
public relay defaults, and the self-hosted relay repository itself.

## Build order (layers, each shippable)

1. `TMDB.Title` + title search move + `tracked_refs` + `title_summary` +
   poster helper + watchlist embed migration + `tab_strip` +
   `show_discovery` rename + Discovery page with the Watchlist tab only.
2. `MediaCentaur.Nostr` (keys, events, filters) with vector tests.
3. `Friends.Identity` + Friends tab identity block.
4. `Nostr.Connection` + fake relay + `Friends.Relay` + `Friends.Connections`
   + Friends tab relay block.
5. `Friends.Friend` + Friends tab roster block.
6. `Recommendations` (schema, translation, sync) + recommend modal + Feed
   tab.
7. Watchlist provenance (`:friend`, `recommendation_id`, "from <nickname>")
   + Status page Friends section.
8. Wiki: new *Friends and Recommendations* page, Settings-Reference
   (`show_discovery`), Troubleshooting (relay rejected, no identity);
   CHANGELOG.
9. **Hardening pass** (after iteration settles): move the Discovery pieces
   under `components/` with stories; keyboard/gamepad navigation on the feed,
   tab strip, Friends tab and recommend modal; wiki Keyboard-and-Gamepad.

## Pointers

- Watchlist foundation: `docs/superpowers/specs/2026-08-18-watchlist-foundation-design.md`,
  plan `docs/superpowers/plans/2026-08-18-watchlist-foundation.md`.
- Nostr: NIP-01 (events/relays/filters), NIP-19 (bech32 entities), NIP-42
  (client authentication), NIP-33 semantics now in NIP-01 (addressable
  events). Relay software for the sibling repo: `strfry`, `khatru`.
- Existing patterns to mirror: `Playback.MpvSession` (retry with
  `Process.send_after`), `Settings.Preferences.BooleanSetting`,
  `TmdbArtwork.HoldProvider`, `EntityModal` shared handlers,
  `MediaCentaurWeb.Live.WatchlistAware`.
