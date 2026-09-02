---
status: active
status_note: design — unparked 2026-09-01 (v1.0.0 shipped 2026-08-19)
started: 2026-06-17
last_updated: 2026-09-02
---
# Friends & recommendations (Nostr backbone)

## Goal

Let a Media Centaur user have **friends** and **send/receive show
recommendations**, where selecting a received recommendation **directly
triggers a download** through the existing acquisition path — all from inside
the app, **with no central server we operate**, and with strong user control and
privacy. This is intended to be a **backbone feature of Media Centaur v2**, not a
v1 item. Recorded now to preserve the design conversation; do *not* start
building until v1 is done.

## Status

**Spec written 2026-09-02; building.** v1.0.0
shipped 2026-08-19, so the parking condition is met. All open questions are
resolved (below). Spec:
`docs/superpowers/specs/2026-09-02-friends-recommendations-design.md`
(includes the unify_design adjudication and an eight-layer build order).
Layers 1a (title convergence,
`docs/superpowers/plans/2026-09-02-title-convergence.md`) and 1b (Discovery
page at `/discovery/watchlist` with `tab_strip` and `show_discovery`,
`docs/superpowers/plans/2026-09-02-discovery-page.md`) landed 2026-09-02 on
main, unpushed. Layer 2 (`MediaCentaur.Nostr`: `Keys`, `Event`, `Filter`;
`bitcoinex` dep) landed 2026-09-02. Layer 3 (Friends identity:
`Social.Identity` on the sensitive `nostr_secret_key` config key, Friends
tab identity block at `/discovery/social`) landed 2026-09-02. Layer 4 (relay
connections: `Nostr.Connection`, `Nostr.FakeRelay`, `Social.Relay`,
`Social.Connections`, relay block) landed 2026-09-02. Layer 5 (roster:
`Social.Friend`, roster block) landed 2026-09-02. Layer 6
(`Recommendations` records/translation/sync, the Recommend modal, and the
Feed tab at `/discovery`) landed 2026-09-02. Layer 7 (watchlist
provenance, console tags, Friends incident assessor + Status tile/widget)
landed 2026-09-02. Layer 8 (docs) landed 2026-09-02: the wiki page
*Friends and Recommendations* plus Settings-Reference / Troubleshooting /
FAQ / Watchlist / Home / _Sidebar entries, and the contributor guide
`docs/friends.md` linked from `CLAUDE.md` and `docs/architecture.md`.
**Shipped as v1.6.0 on 2026-09-02** (layers 1–8 plus dev tooling; relay
repo v0.1.0). Dev tooling landed 2026-09-02 (spec
`docs/superpowers/specs/2026-09-02-social-dev-tooling-design.md`): `just
social` walkthrough, `just social-up/down/reset/status/recommend/feed`,
`mix social.dev` (dev friend key + `Nostr.OneShot` sessions), and
`scripts/dev-relay` in the relay repo. Next: owner review of the full
campaign, then layer 9 (hardening) after iteration.

## Decisions made

* `2026-06-17` — **No central server.** Two friends' instances are assumed
  *not* directly reachable (home routers, no inbound connectivity). Started
  toward a pure out-of-band "shareable artifact" (sneakernet) model, then
  pivoted to a relay/feed substrate.
* `2026-06-17` — **Protocol = Nostr.** Chosen over Matrix (heavier; someone must
  host & expose a homeserver) and a custom Phoenix relay (reintroduces the
  inbound-connectivity problem). Nostr is the only option where a friend group
  can host **nothing at all** (free public relays) yet *upgrade* to
  self-hosting for full control — "control on a slider, not a fork." Mapping:
  a **recommendation** = a signed event kind; a **friend** = a pubkey you
  follow; a **relay** = the dumb pipe.
* `2026-06-17` — **Identity = Nostr keypair** (secp256k1). Gives cryptographic
  "✓ verified from Alex," a real local roster, and per-friend history — all
  offline — for free, instead of a typed-name text field or trust-on-first-use.
* `2026-06-17` — **Privacy = "both" (the control slider).** Support **public
  feeds** (published to public relays, world-readable — good for "follow someone
  whose taste you trust") *and* **private feeds** (a relay the group self-hosts
  with a write/read allowlist, e.g. `strfry`/`khatru`). Directed recommendations
  can be end-to-end encrypted (NIP-17 / NIP-44) so they ride over any relay but
  only the recipient can read them. Friendly default still TBD (see open
  questions).
* `2026-06-17` — **NIF is acceptable.** secp256k1 Schnorr signing likely needs a
  native dependency; since it compiles **into the release binary**, it does not
  grow the end user's install footprint in a way the owner cares about. (Squares
  with the "no extra user-install deps" preference: the concern is the *user's*
  footprint, not bundled build artifacts.) Does touch the macOS/Linux build —
  flag during planning.
* `2026-06-17` — **Reuse the acquisition path.** "Select a recommendation →
  download" routes through the existing `acquisition` / `search` / `tmdb`
  pursuit machinery; the new feature only produces the TMDB reference + a
  human-confirm step, it does not own downloading.
* `2026-08-18` — **Q4 resolved: broadcast-first, directed-capable.** The core
  gesture is a published feed followers browse (Nostr-native, useful solo as a
  public taste page — mitigates cold start). The data model keeps an optional
  recipient so directed recommendations can be added later without reshaping.
* `2026-08-18` — **Foundation designed and built: local watchlist
  (`Discovery` context).** Received recommendations will land as candidates in
  a local watchlist with provenance, triaged on an existing surface —
  shrinking this campaign's build to transport + identity. Shipped same day
  (watchlist_items table, `/watchlist` page, search-row + detail toggles;
  `source` enum is the provenance seam `:friend` extends). See
  `docs/superpowers/specs/2026-08-18-watchlist-foundation-design.md`.

* `2026-09-02` — **Payload = title snapshot + optional note.** No episode
  pointer, no reactions (additive later).
* `2026-09-02` — **Feed, not auto-land.** Received recommendations are browsed
  on a Feed tab; adding to the watchlist is the user's act.
* `2026-09-02` — **Discovery page.** Watchlist page becomes `/discovery` with
  Feed, Watchlist and Friends tabs (identity, relays, roster live on the
  Friends tab, not in Settings); later discovery sources join it.
  `show_watchlist` preference renamed `show_discovery`.
* `2026-09-02` — **Iterate light, harden after.** New UI pieces are function
  components under `live/discovery_live/` (no MC0009 stories) and get no
  input-system support in the first iteration; a scheduled hardening pass
  moves them under `components/` with stories and adds navigation.
* `2026-09-02` — **Own Status section** (health + aggregates, link to the
  Friends tab).
* `2026-09-02` — **Private first.** No default relays; the group's
  self-hosted allowlist relay is the first target (separate org repo, out of
  scope here); public relays are extra entries. Client implements NIP-42.
* `2026-09-02` — **Keys: generate silently, export/import on demand.** No
  passphrase; nsec stored as a sensitive Settings key.
* `2026-09-02` — **Friend = pasted npub + local nickname.** No profile events.
* `2026-09-02` — **Recommend action** on library detail modals and watchlist
  rows only.
* `2026-09-02` — **Transport = long-lived `Nostr.Connection` per relay**;
  thin in-house client over `mint_web_socket`; **no NIF** (`bitcoinex`
  pure-Elixir Schnorr: sign ≈3 ms, verify ≈1.3 ms measured).
* `2026-09-02` — **Event kind 32160** (addressable, `d` = `tmdb:<type>:<id>`).
* `2026-09-02` — **`decimal` overridden to `~> 3.0`.** `bitcoinex` 0.3.0 still
  requires `decimal ~> 1.0 or ~> 2.0`, and every `decimal` below 3.0.0 carries
  GHSA-rhv4-8758-jx7v, which `mix deps.audit` fails on. `bitcoinex` touches
  `Decimal` only in `LightningNetwork.Invoice` (calls unchanged in 3.x) and we
  never call it, so `mix.exs` carries `{:decimal, "~> 3.0", override: true}`
  rather than a vulnerable pin. Revisit when `bitcoinex` widens its
  requirement.
* `2026-09-02` — **Feed decoration lives in the web layer.**
  `Recommendations.list_feed/0` returns the record plus the friend's
  nickname (and, for an own row, `own?: true` / `nickname: nil`) —
  Recommendations depends on Friends but not on Discovery or Library.
  `DiscoveryLive` joins the rest (`Library.ExternalIds.tmdb_owners/1`,
  `Discovery.watchlisted_refs/0`) into `library_owner_id` /
  `on_watchlist?` / `poster_url`. The only Boundary-legal reading of the
  spec's `list_feed/0` sentence.
* `2026-09-02` — **Own recommendations appear in the Feed marked "You"**
  (spec UI › Feed; the layer-6 plan had dropped this).
* `2026-09-02` — **The detail page's Recommend control is gated by
  `show_discovery`** — the same preference that gates the Discovery sidebar
  entry, because the friend network is a preview and this is the one control
  on the entity modal that belongs to it. Watchlist rows need no extra gate:
  they are only reachable on the Discovery page.
* `2026-09-02` — **Feed time is `Format.relative_ago/1` as it stands**
  ("3d ago"). No second time vocabulary for one surface.
* `2026-09-02` — **unify_design adjudication accepted** (≈ +1 session):
  `TMDB.Title` embedded schema replaces `TitleResult`; rows embed it;
  `tracked?` → ref-set attr; shared `title_summary`, poster helper and
  `tab_strip`; Recommendations artwork holds.

* `2026-09-02` — **Vocabulary: "Social" is the subsystem; "friend" is a
  roster entry.** "Friends" had named the subsystem (Status tile, incident
  component, console tag), the bounded context, the Discovery tab and the
  roster block at once. Renamed: context `MediaCentaur.Friends` →
  `MediaCentaur.Social`; topics `social:updates` / `social:connections`;
  console tags collapse to `:nostr` (wire) + `:social`; board key, incident
  component and widget `:social`; tab `/discovery/social` labelled
  **Social**; contributor guide `docs/social.md`; wiki page *Social*. Stored
  incidents keyed `friends` are left as they are. Glossary elevated to
  `docs/GLOSSARY.md`.

* `2026-09-02` — **Dev tooling: `just` front door, each repo owns its half.**
  The relay repo's `scripts/dev-relay` builds the image, writes the
  allowlist TOML and runs the container on `ws://127.0.0.1:2173`; the app's
  `mix social.dev` holds a gitignored dev-friend key (`priv/dev-social/`)
  and publishes / reads through `Nostr.OneShot`, a synchronous session over
  `Nostr.Connection`. The dev app's npub is pasted once (`just social-up
  npub1…`); the friend's title snapshot comes from flags, never TMDB. A
  second app instance is deferred until a feature needs two real UIs. Bare
  `just` now lists recipes instead of running `deploy`.

* `2026-09-02` — **Identity and relays move to Settings → Social** (owner
  request after v1.6.0; reverses spec decision "not a Settings section").
  `SettingsLive.SocialSection` holds the npub/secret-key/import block and
  the relay list; the Discovery page's Social tab keeps only the roster
  and points at Settings. The section is always shown (relays connect
  regardless of the Discovery preference) and is where the identity is
  minted. Wiki, relay docs and `just social` updated.
* `2026-09-02` — **The Discovery tab is "Friends"** (`/discovery/friends`,
  `live_action :friends`): Social is the set of features; Friends is the
  roster feature within it. Status widget links there as *Open Friends*.

## Open questions

*All resolved 2026-09-02 — see Decisions and the spec. Kept for history.*

1. **Recommendation payload shape** — TMDB ref (movie/series) + optional note;
   maybe "where to start" (episode), maybe a reaction/reply primitive. Keep
   minimal (YAGNI; owner dislikes completeness padding).
2. **Default privacy posture** — encrypted-over-public so it "just works," with
   self-hosted relay as the lock-it-down upgrade?
3. **Key & friend management UX** — where the keypair lives, the friend-add
   handshake (exchange npubs), relay configuration UI, backup/restore of the
   secret key.
4. **Elixir Nostr support** — *researched 2026-09-01:* the hex Nostr clients
   (`nostr` 0.1.3, `nostr_basics`) are unmaintained since 2023 → thin in-house
   client over `mint_web_socket`. `bitcoinex` 0.3.0 (pure Elixir, maintained,
   only dep `decimal`) ships BIP-340 Schnorr sign/verify + bech32, so **no NIF
   is needed**; `ex_secp256k1` (Rustler) stays the fallback if pure-Elixir
   verify proves too slow. Decision pending the spec.

## Architectural sketch (provisional)

* New bounded context. **Separate transport from domain**: a Nostr transport
  layer (long-lived WebSocket connection processes per relay, publish/subscribe
  by author+kind+tags — "Atom feed of communications") vs a `Recommendations`
  domain. Inbound signed events pass through an **anti-corruption translation**
  into domain recommendations (mirrors existing event-translation patterns),
  persisted via Ecto, broadcast to LiveView over PubSub. This is a comfortable
  fit for the app's OTP + PubSub + event-translation grain.
* Human-confirm before any download (no auto-acquire from an imported/received
  artifact) — aligns with the existing `user_decision_requested` pattern.

## Next steps

* ~~CHANGELOG~~ shipped in v1.6.0.
* **Drop the watchlist flat snapshot columns** (`name`, `year`,
  `release_date`, `poster_path`, `overview`) and remove the transitional
  `name` write in `WatchlistItem.create_changeset/2` — a schema migration that
  MUST ship in the **very next release** after the embed (v1.6.0 shipped the
  embed on 2026-09-02 → the drop goes in v1.7.0, the very next release): until it lands, a
  watchlist row written by the old release during the seconds-wide upgrade
  window (`title = NULL`) crashes `/watchlist` on mount, and only the drop
  migration's inline heal repairs it. It MUST first run the same
  `UPDATE watchlist_items SET title = json_object(…) WHERE title IS NULL`
  inline (per-line Credo carve-out for MC0015) before `remove`-ing the
  columns: schema migrations run before data migrations, so a skipped-release
  upgrade reaches the drop before the backfill; and the old release can write
  flat-only rows between `migrate` and restart.
* **Board alias:** `:nostr`/`:recommendations` log incidents count on the
  Friends tile (`HealthBoard.normalize/1`); the pre-existing gap that
  `:subsystem` incidents never reach the board remains (ErrorReports).
* **`:subsystem` incidents do not reach the health board.**
  `BucketCache.from_incidents/1` keeps only fingerprint-keyed (`:log`)
  rows, and the `Evaluator` raises faults with no `message`, so every
  assessor's verdict — `Social.IncidentContext` included, and
  `download_client_unreachable` / `search_provider_unreachable` before it
  — is stored durably and colours nothing. The Friends tile therefore
  reads "No issues" even with every relay down. Pre-existing and
  system-wide; fixing it means giving `:subsystem` incidents a synthetic
  grouping key and a per-kind headline (the three Friends kinds are
  **Relay rejected this identity**, **No relay reachable**, **A relay is
  unreachable**), which is an `ErrorReports` change, not a Friends one.
* **Hardening pass** after iteration settles (spec decision 11).
* **Plan modal selection header → `title_summary`** (spec unification
  decision 4): converges when the plan modal is next touched; not before.
* **`Review.search_tmdb/2` → `TMDB.TitleSearch` / `TMDB.Title`**: the review
  page's TMDB search still returns its own map shape; converge when Review
  search is next touched.

* **Non-member rejection by `social-relay` surfaces as `last_error`, not
  as *Relay rejected this identity*.** From the relay campaign (shipped
  v0.1.0, 2026-09-02; contract in `../social-relay/docs/protocol.md`).
  khatru cannot refuse an `AUTH` event, so a key that is not on the
  allowlist gets `OK true` for its auth and then
  `["CLOSED", "feed", "restricted: this key is not a member of this relay"]`,
  the same on `own:<url>`, and `OK false` with that reason on every
  `EVENT`. The row stays **Connected** with the reason as its error.
  Proposed rule: a `CLOSED` whose reason starts with `restricted:` on
  `feed`, from a relay that has accepted this identity's `AUTH`, is an
  authentication failure (`:auth_failed`). Match on the prefix only.

## Completion criteria

*(Provisional — refine when the campaign is unparked for real.)*

* A user can generate a keypair, add a friend, and configure at least one relay
  (public default; self-hosted optional) from inside the app.
* A user can send a recommendation and a friend receives it, attributed and
  identity-verified, with no server operated by us.
* Selecting a received recommendation triggers acquisition through the existing
  pursuit path after an explicit human confirm.
* Public-and-private feed modes both work; private mode requires only a
  self-hosted relay, nothing exposed by any individual's home instance.
* Wiki + Settings docs updated for key management and relay setup.

## Pointers

* **Private relay repo:** `../social-relay` (campaign
  `campaigns/private-relay-v1.md` there). Decided 2026-09-02: khatru
  (`fiatjaf.com/nostr/khatru`), SQLite store, TOML allowlist, challenge on
  connect, kind 32160 only. Built by its own Claude instance; app-side
  follow-ups arrive here under its **Cross-repo** section.
* Acquisition entry points: `MediaCentaur.Acquisition`, `MediaCentaur.Search`,
  `MediaCentaur.Tmdb`.
* Nostr: NIP-01 (events/relays/subscriptions), NIP-17 + NIP-44 (private DMs /
  encryption), NIP-42 (relay auth/allowlist). Relay implementations: `strfry`,
  `khatru`, `nostr-rs-relay`.
* No prior art in-repo: the app currently has **no auth / user / account /
  identity-of-person** model — this is greenfield.
