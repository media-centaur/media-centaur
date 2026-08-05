---
status: parked
status_note: parked — v2 backbone (deferred until v1 is complete)
started: 2026-06-17
last_updated: 2026-06-17
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

**Parked / design-in-progress.** The connectivity and protocol direction is
settled (Nostr); one core UX fork (Q4) and several detail decisions are still
open. No code, no spec, no plan yet. Next session resumes at Q4 below, then runs
the normal brainstorm → spec → plan flow.

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

## Open questions (resume here)

1. **Q4 — the core gesture (unresolved).** Is the heart of the feature a
   **broadcast feed** (you publish recs; followers browse them — Nostr-native,
   makes "host your own feed" shine; leaned this way), a **directed
   recommendation** ("send *this* to Alex," an inbox, inherently private), or
   **genuinely both** co-equal from day one? This decides the event kinds and
   whether the primary surface is a "Friends' Feed" page vs an "Inbox."
2. **Recommendation payload shape** — TMDB ref (movie/series) + optional note;
   maybe "where to start" (episode), maybe a reaction/reply primitive. Keep
   minimal (YAGNI; owner dislikes completeness padding).
3. **Default privacy posture** — encrypted-over-public so it "just works," with
   self-hosted relay as the lock-it-down upgrade?
4. **Key & friend management UX** — where the keypair lives, the friend-add
   handshake (exchange npubs), relay configuration UI, backup/restore of the
   secret key.
5. **Elixir Nostr support** — existing hex lib vs a thin in-house client (it's
   websocket + JSON + Schnorr sign/verify); pick the Schnorr NIF.

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

* Acquisition entry points: `MediaCentaur.Acquisition`, `MediaCentaur.Search`,
  `MediaCentaur.Tmdb`.
* Nostr: NIP-01 (events/relays/subscriptions), NIP-17 + NIP-44 (private DMs /
  encryption), NIP-42 (relay auth/allowlist). Relay implementations: `strfry`,
  `khatru`, `nostr-rs-relay`.
* No prior art in-repo: the app currently has **no auth / user / account /
  identity-of-person** model — this is greenfield.
